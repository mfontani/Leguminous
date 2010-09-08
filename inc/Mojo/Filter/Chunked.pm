package Mojo::Filter::Chunked;

use strict;
use warnings;

use base 'Mojo::Filter';

# Here's to alcohol, the cause of—and solution to—all life's problems.
sub build {
    my ($self, $chunk) = @_;

    # Done
    return '' if ($self->{_state} || '') eq 'done';

    # Shortcut
    return unless defined $chunk;

    my $chunk_length = length $chunk;

    # Trailing headers
    my $headers = ref $chunk && $chunk->isa('Mojo::Headers') ? 1 : 0;

    # End
    my $formatted = '';
    if ($headers || ($chunk_length == 0)) {
        $self->{_state} = 'done';

        # Normal end
        $formatted = "\x0d\x0a0\x0d\x0a";

        # Trailing headers
        $formatted .= $headers ? "$chunk\x0d\x0a\x0d\x0a" : "\x0d\x0a";
    }

    # Separator
    else {

        # First chunk has no leading CRLF
        $formatted = "\x0d\x0a" if $self->{_state};
        $self->{_state} = 'chunks';

        # Chunk
        $formatted .= sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
    }

    return $formatted;
}

sub is_done {
    return 1 if (shift->{_state} || '') eq 'done';
    return;
}

sub parse {
    my $self = shift;

    # Trailing headers
    if (($self->{_state} || '') eq 'trailing_headers') {
        $self->_parse_trailing_headers;
        return $self;
    }

    # New chunk (ignore the chunk extension)
    my $filter  = $self->input_buffer;
    my $content = $filter->to_string;
    my $buffer  = $self->output_buffer;
    while ($content =~ /^((?:\x0d?\x0a)?([\da-fA-F]+).*\x0d?\x0a)/) {
        my $header = $1;
        my $length = hex($2);

        # Last chunk
        if ($length == 0) {
            $filter->remove(length $header);
            $self->{_state} = 'trailing_headers';
            last;
        }

        # Read chunk
        else {

            # Whole chunk
            if (length $content >= (length($header) + $length)) {

                # Remove header
                $content =~ s/^$header//;
                $filter->remove(length $header);

                # Remove payload
                substr $content, 0, $length, '';
                $buffer->add_chunk($filter->remove($length));

                # Remove newline at end of chunk
                $content =~ s/^(\x0d?\x0a)// and $filter->remove(length $1);
            }

            # Not a whole chunk, wait for more data
            else {last}
        }
    }

    # Trailing headers
    $self->_parse_trailing_headers
      if ($self->{_state} || '') eq 'trailing_headers';
}

sub _parse_trailing_headers {
    my $self = shift;

    # Parse
    my $headers = $self->headers;
    $headers->parse;

    # Done
    if ($headers->is_done) {
        $self->_remove_chunked_encoding;
        $self->{_state} = 'done';
    }
}

sub _remove_chunked_encoding {
    my $self = shift;

    # Remove encoding
    my $headers  = $self->headers;
    my $encoding = $headers->transfer_encoding;
    $encoding =~ s/,?\s*chunked//ig;
    $encoding
      ? $headers->transfer_encoding($encoding)
      : $headers->remove('Transfer-Encoding');
    $headers->content_length($self->output_buffer->raw_size);
}

1;
__END__

=head1 NAME

Mojo::Filter::Chunked - HTTP 1.1 Chunked Filter

=head1 SYNOPSIS

    use Mojo::Filter::Chunked;

    my $chunked = Mojo::Filter::Chunked->new;

    $chunked->headers(Mojo::Headers->new);
    $chunked->input_buffer(Mojo::ByteStream->new);
    $chunked->output_buffer(Mojo::ByteStream->new);

    $chunked->input_buffer->add_chunk("6\r\nHello!")
    $chunked->parse;
    print $chunked->output_buffer->empty;

    print $chunked->build('Hello World!');

=head1 DESCRIPTION

L<Mojo::Filter::Chunked> is a filter for the HTTP 1.1 chunked transfer
encoding as described in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Filter::Chunked> inherits all attributes from L<Mojo::Filter>.

=head1 METHODS

L<Mojo::Filter::Chunked> inherits all methods from L<Mojo::Filter> and
implements the following new ones.

=head2 C<build>

    my $formatted = $filter->build('Hello World!');

Build chunked content.

=head2 C<is_done>

    my $done = $filter->is_done;

Check if filter is done.

=head2 C<parse>

    $filter = $filter->parse;

Filter chunked content.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
