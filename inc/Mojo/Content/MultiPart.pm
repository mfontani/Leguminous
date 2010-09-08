package Mojo::Content::MultiPart;

use strict;
use warnings;

use base 'Mojo::Content';

use Mojo::ByteStream 'b';

__PACKAGE__->attr(parts => sub { [] });

sub body_contains {
    my ($self, $chunk) = @_;

    # Check parts
    my $found = 0;
    for my $part (@{$self->parts}) {
        my $headers = $part->build_headers;
        $found += 1 if $headers =~ /$chunk/g;
        $found += $part->body_contains($chunk);
    }

    # Found
    return $found ? 1 : 0;
}

sub body_size {
    my $self = shift;

    # Check for Content-Lenght header
    my $content_length = $self->headers->content_length;
    return $content_length if $content_length;

    # Boundary
    my $boundary = $self->build_boundary;

    # Calculate length of whole body
    my $boundary_length = length($boundary) + 6;
    my $length          = 0;
    $length += $boundary_length - 2;
    for my $part (@{$self->parts}) {

        # Header
        $length += $part->header_size;

        # Body
        $length += $part->body_size;

        # Boundary
        $length += $boundary_length;
    }

    return $length;
}

sub build_boundary {
    my $self = shift;

    # Check for existing boundary
    my $headers = $self->headers;
    my $type = $headers->content_type || '';
    my $boundary;
    $type =~ /boundary=\"?([^\s\"]+)\"?/i and $boundary = $1;
    return $boundary if $boundary;

    # Generate and check boundary
    my $size = 1;
    while (1) {

        # Mostly taken from LWP
        $boundary =
          b(join('', map chr(rand(256)), 1 .. $size * 3))->b64_encode;
        $boundary =~ s/\W/X/g;

        # Check parts for boundary
        last unless $self->body_contains($boundary);
        $size++;
    }

    # Add boundary to Content-Type header
    $type =~ /^(.*multipart\/[^;]+)(.*)$/;
    my $before = $1 || 'multipart/mixed';
    my $after  = $2 || '';
    $headers->content_type("$before; boundary=$boundary$after");

    return $boundary;
}

sub get_body_chunk {
    my ($self, $offset) = @_;

    # Body generator
    return $self->generate_body_chunk($offset) if $self->body_cb;

    # Multipart
    my $boundary        = $self->build_boundary;
    my $boundary_length = length($boundary) + 6;
    my $length          = $boundary_length - 2;

    # First boundary
    return substr "--$boundary\x0d\x0a", $offset if $length > $offset;

    # Parts
    my $parts = $self->parts;
    for (my $i = 0; $i < @$parts; $i++) {
        my $part = $parts->[$i];

        # Headers
        my $header_length = $part->header_size;
        return $part->get_header_chunk($offset - $length)
          if ($length + $header_length) > $offset;
        $length += $header_length;

        # Content
        my $content_length = $part->body_size;
        return $part->get_body_chunk($offset - $length)
          if ($length + $content_length) > $offset;
        $length += $content_length;

        # Boundary
        if (($length + $boundary_length) > $offset) {

            # Last boundary
            return substr "\x0d\x0a--$boundary--", $offset - $length
              if $#{$parts} == $i;

            # Middle boundary
            return substr "\x0d\x0a--$boundary\x0d\x0a", $offset - $length;
        }
        $length += $boundary_length;
    }
}

sub parse {
    my $self = shift;

    # Parse headers and filter body
    $self->SUPER::parse(@_);

    # Custom body parser
    return $self if $self->body_cb;

    # Upgrade state
    $self->{_state} = 'multipart_preamble'
      if ($self->{_state} || '') eq 'body';

    # Parse multipart content
    $self->_parse_multipart;

    return $self;
}

sub _parse_multipart {
    my $self = shift;

    # Need a boundary
    $self->headers->content_type
      =~ /.*boundary=\"*([a-zA-Z0-9\'\(\)\,\.\:\?\-\_\+\/]+).*/;
    my $boundary = $1;

    # Boundary missing
    return $self->error('Multipart boundary missing.', 400) unless $boundary;

    # Parse
    while (1) {

        # Done
        last if $self->is_done;

        # Preamble
        if (($self->{_state} || '') eq 'multipart_preamble') {
            last unless $self->_parse_multipart_preamble($boundary);
        }

        # Boundary
        elsif (($self->{_state} || '') eq 'multipart_boundary') {
            last unless $self->_parse_multipart_boundary($boundary);
        }

        # Body
        elsif (($self->{_state} || '') eq 'multipart_body') {
            last unless $self->_parse_multipart_body($boundary);
        }
    }
}

sub _parse_multipart_body {
    my ($self, $boundary) = @_;

    # Whole part in buffer
    my $buffer = $self->buffer;
    my $pos    = $buffer->contains("\x0d\x0a--$boundary");
    if ($pos < 0) {
        my $length = $buffer->size - (length($boundary) + 8);
        return unless $length > 0;

        # Store chunk
        my $chunk = $buffer->remove($length);
        $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
        return;
    }

    # Store chunk
    my $chunk = $buffer->remove($pos);
    $self->parts->[-1] = $self->parts->[-1]->parse($chunk);
    $self->{_state} = 'multipart_boundary';
    return 1;
}

sub _parse_multipart_boundary {
    my ($self, $boundary) = @_;

    # Boundary begins
    my $buffer = $self->buffer;
    if ($buffer->contains("\x0d\x0a--$boundary\x0d\x0a") == 0) {
        $buffer->remove(length($boundary) + 6);

        # New part
        push @{$self->parts}, Mojo::Content::Single->new(relaxed => 1);
        $self->{_state} = 'multipart_body';
        return 1;
    }

    # Boundary ends
    my $end = "\x0d\x0a--$boundary--";
    if ($buffer->contains($end) == 0) {
        $buffer->remove(length $end);

        # Done
        $self->{_state} = 'done';
    }

    return;
}

sub _parse_multipart_preamble {
    my ($self, $boundary) = @_;

    # Replace preamble with carriage return and line feed
    my $buffer = $self->buffer;
    my $pos    = $buffer->contains("--$boundary");
    unless ($pos < 0) {
        $buffer->remove($pos, "\x0d\x0a");

        # Parse boundary
        $self->{_state} = 'multipart_boundary';
        return 1;
    }

    # No boundary yet
    return;
}

1;
__END__

=head1 NAME

Mojo::Content::MultiPart - HTTP 1.1 MultiPart Content Container

=head1 SYNOPSIS

    use Mojo::Content::MultiPart;

    my $content = Mojo::Content::MultiPart->new;
    $content->parse('Content-Type: multipart/mixed; boundary=---foobar');
    my $part = $content->parts->[4];

=head1 DESCRIPTION

L<Mojo::Content::MultiPart> is a container for HTTP 1.1 multipart content as
described in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Content::MultiPart> inherits all attributes from L<Mojo::Content>
and implements the following new ones.

=head2 C<parts>

    my $parts = $content->parts;

Content parts embedded in this multipart content.

=head1 METHODS

L<Mojo::Content::MultiPart> inherits all methods from L<Mojo::Content> and
implements the following new ones.

=head2 C<body_contains>

    my $found = $content->body_contains('foobarbaz');

Check if content parts contain a specific string.

=head2 C<body_size>

    my $size = $content->body_size;

Content size in bytes.

=head2 C<build_boundary>

    my $boundary = $content->build_boundary;

Generate a suitable boundary for content.

=head2 C<get_body_chunk>

    my $chunk = $content->get_body_chunk(0);

Get a chunk of content starting from a specfic position.

=head2 C<parse>

    $content = $content->parse('Content-Type: multipart/mixed');

Parse content.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
