package Mojo::Parameters;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::ByteStream 'b';
use Mojo::URL;

__PACKAGE__->attr(charset        => 'UTF-8');
__PACKAGE__->attr(pair_separator => '&');
__PACKAGE__->attr(params         => sub { [] });

# Yeah, Moe, that team sure did suck last night. They just plain sucked!
# I've seen teams suck before,
# but they were the suckiest bunch of sucks that ever sucked!
# HOMER!
# I gotta go Moe my damn weiner kids are listening.
sub new {
    my $self = shift->SUPER::new();

    # Hash/Array
    if (defined $_[1]) { $self->append(@_) }

    # String
    else { $self->parse(@_) }

    return $self;
}

sub append {
    my ($self, @params) = @_;

    # Filter array values
    for (my $i = 1; $i < @params; $i += 2) {
        next if ref $params[$i] ne 'ARRAY';
        push @params, map { ($params[$i - 1], $_) } @{$params[$i]};
        splice @params, $i - 1, 2;
    }

    # Append
    push @{$self->params}, map { defined $_ ? "$_" : '' } @params;

    return $self;
}

sub clone {
    my $self  = shift;
    my $clone = Mojo::Parameters->new;
    $clone->pair_separator($self->pair_separator);
    $clone->params([@{$self->params}]);
    return $clone;
}

sub merge {
    my $self = shift;
    push @{$self->params}, @{$_->params} for @_;
    return $self;
}

sub param {
    my $self = shift;
    my $name = shift;

    # List names
    return sort keys %{$self->to_hash} unless $name;

    # Cleanup
    $self->remove($name) if defined $_[0];

    # Append
    for my $value (@_) {
        $self->append($name, $value);
    }

    # List values
    my @values;
    my $params = $self->params;
    for (my $i = 0; $i < @$params; $i += 2) {
        push @values, $params->[$i + 1] if $params->[$i] eq $name;
    }

    return wantarray ? @values : $values[0];
}

sub parse {
    my $self   = shift;
    my $string = shift;

    # Shortcut
    return $self unless defined $string;

    # Clear
    $self->params([]);

    # Charset
    my $charset = $self->charset;

    # Detect query string without key/value pairs
    if ($string !~ /\=/) {
        $string =~ s/\+/\ /g;

        # Unescape
        $string = b($string)->url_unescape->to_string;

        # Try to decode
        if ($charset) {
            my $backup = $string;
            $string = b($string)->decode($charset)->to_string;
            $string = $backup unless defined $string;
        }

        $self->params([$string, undef]);
        return $self;
    }

    # Detect pair separator for reconstruction
    $self->pair_separator(';') if $string =~ /\;/ && $string !~ /\&/;

    # W3C suggests to also accept ";" as a separator
    for my $pair (split /[\&\;]+/, $string) {

        # Parse
        $pair =~ /^([^\=]*)(?:=(.*))?$/;
        my $name  = $1;
        my $value = $2;

        # Replace "+" with whitespace
        $name  =~ s/\+/\ /g if $name;
        $value =~ s/\+/\ /g if $value;

        # Unescape
        $name  = b($name)->url_unescape->to_string;
        $value = b($value)->url_unescape->to_string;

        # Try to decode
        if ($charset) {
            my $nbackup = $name;
            my $vbackup = $value;
            $name  = b($name)->decode($charset)->to_string;
            $value = b($value)->decode($charset)->to_string;
            $name  = $nbackup unless defined $name;
            $value = $vbackup unless defined $value;
        }

        push @{$self->params}, $name, $value;
    }

    return $self;
}

# Don't kid yourself, Jimmy. If a cow ever got the chance,
# he'd eat you and everyone you care about!
sub remove {
    my ($self, $name) = @_;

    $name = '' unless defined $name;

    # Remove
    my $params = $self->params;
    for (my $i = 0; $i < @$params;) {
        if ($params->[$i] eq $name) { splice @$params, $i, 2 }
        else                        { $i += 2 }
    }
    $self->params($params);

    return $self;
}

sub to_hash {
    my $self   = shift;
    my $params = $self->params;

    # Format
    my %params;
    for (my $i = 0; $i < @$params; $i += 2) {
        my $name  = $params->[$i];
        my $value = $params->[$i + 1];

        # Array
        if (exists $params{$name}) {
            $params{$name} = [$params{$name}]
              unless ref $params{$name} eq 'ARRAY';
            push @{$params{$name}}, $value;
        }

        # String
        else { $params{$name} = $value }
    }

    return \%params;
}

sub to_string {
    my $self   = shift;
    my $params = $self->params;

    # Shortcut
    return unless @{$self->params};

    # Format
    my @params;
    my $charset = $self->charset;
    for (my $i = 0; $i < @$params; $i += 2) {
        my $name  = $params->[$i];
        my $value = $params->[$i + 1];

        # *( pchar / "/" / "?" ) with the exception of ";", "&" and "="
        $name  = b($name)->encode($charset)->url_escape($Mojo::URL::PARAM);
        $value = b($value)->encode($charset)->url_escape($Mojo::URL::PARAM)
          if $value;

        # Replace whitespace with "+"
        $name =~ s/\%20/\+/g;
        $value =~ s/\%20/\+/g if $value;

        push @params, defined $value ? "$name=$value" : "$name";
    }

    my $separator = $self->pair_separator;
    return join $separator, @params;
}

1;
__END__

=head1 NAME

Mojo::Parameters - Parameter Container

=head1 SYNOPSIS

    use Mojo::Parameters;

    my $params = Mojo::Parameters->new(foo => 'bar', baz => 23);
    print "$params";

=head1 DESCRIPTION

L<Mojo::Parameters> is a container for form parameters.

=head1 ATTRIBUTES

L<Mojo::Parameters> implements the following attributes.

=head2 C<charset>

    my $charset = $params->charset;
    $params     = $params->charset('UTF-8');

Charset used for decoding parameters.

=head2 C<pair_separator>

    my $separator = $params->pair_separator;
    $params       = $params->pair_separator(';');

Separator for parameter pairs.

=head2 C<params>

    my $parameters = $params->params;
    $params        = $params->params(foo => 'b;ar', baz => 23);

The parameters.

=head1 METHODS

L<Mojo::Parameters> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $params = Mojo::Parameters->new;
    my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
    my $params = Mojo::Parameters->new(foo => 'b;ar', baz => 23);

Construct a new L<Mojo::Parameters> object.

=head2 C<append>

    $params = $params->append(foo => 'ba;r');

Append parameters.

=head2 C<clone>

    my $params2 = $params->clone;

Clone parameters.

=head2 C<merge>

    $params = $params->merge($params2, $params3);

Merge parameters.

=head2 C<param>

    my $foo = $params->param('foo');
    my @foo = $params->param('foo');
    my $foo = $params->param(foo => 'ba;r');

Check parameter values.

=head2 C<parse>

    $params = $params->parse('foo=b%3Bar&baz=23');

Parse parameters.

=head2 C<remove>

    $params = $params->remove('foo');

Remove a parameter.

=head2 C<to_hash>

    my $hash = $params->to_hash;

Turn parameters into a hashref.

=head2 C<to_string>

    my $string = $params->to_string;

Turn parameters into a string.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
