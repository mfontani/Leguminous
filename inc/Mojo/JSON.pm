package Mojo::JSON;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';

__PACKAGE__->attr('error');

# Literal names
our $FALSE = Mojo::JSON::_Bool->new(0);
our $TRUE  = Mojo::JSON::_Bool->new(1);

# Regex
my $WHITESPACE_RE  = qr/[\x20\x09\x0a\x0d]*/;
my $ARRAY_BEGIN_RE = qr/^$WHITESPACE_RE\[/;
my $ARRAY_END_RE   = qr/^$WHITESPACE_RE\]/;
my $ESCAPE_RE      = qr/
    ([\\\"\/\b\f\n\r\t])   # Special character
    |
    ([\x00-\x1f])          # Control character
/x;
my $NAME_SEPARATOR_RE = qr/^$WHITESPACE_RE\:/;
my $NAMES_RE          = qr/^$WHITESPACE_RE(false|null|true)/;
my $NUMBER_RE         = qr/
    ^
    $WHITESPACE_RE
    (
    -?                  # Minus
    (?:0|[1-9]\d*)      # Digits
    (?:\.\d+)?          # Fraction
    (?:[eE][+-]?\d+)?   # Exponent
    )
/x;
my $OBJECT_BEGIN_RE = qr/^$WHITESPACE_RE\{/;
my $OBJECT_END_RE   = qr/^$WHITESPACE_RE\}/;
my $STRING_RE       = qr/
    ^
    $WHITESPACE_RE
    \"                                    # Quotation mark
    ((?:
    \\u[0-9a-fA-F]{4}                     # Escaped unicode character
    |
    \\[\"\/\\bfnrt]                       # Escaped special characters
    |
    [\x20-\x21\x23-\x5b\x5d-\x{10ffff}]   # Unescaped characters
    )*)
    \"                                    # Quotation mark
/x;
my $UNESCAPE_RE = qr/
    (\\[\"\/\\bfnrt])                 # Special character
    |
    \\u([dD][89abAB][0-9a-fA-F]{2})   # High surrogate
    \\u([dD][c-fC-F][0-9a-fA-F]{2})   # Low surrogate
    |
    \\u(                              # Unicode character (no surrogates)
    [0-9A-Ca-cE-Fe-f][0-9A-Fa-f]{3}   # U+0000 - U+CEEE, U+E000 - U+FFFF
    |
    [Dd][0-7][0-9A-Fa-f]{2}           # U+D000 - U+D7FF
    )
/x;
my $VALUE_SEPARATOR_RE = qr/^$WHITESPACE_RE\,/;

# Escaped special character map
my $ESCAPE = {
    '\"'   => "\x22",
    '\\\\' => "\x5c",
    '\/'   => "\x2f",
    '\b'   => "\x8",
    '\f'   => "\xC",
    '\n'   => "\xA",
    '\r'   => "\xD",
    '\t'   => "\x9"
};
my $REVERSE_ESCAPE = {};
for my $key (keys %$ESCAPE) { $REVERSE_ESCAPE->{$ESCAPE->{$key}} = $key }

# Byte order marks
my $BOM_RE = qr/
    (?:
    \357\273\277   # UTF-8
    |
    \377\376\0\0   # UTF-32LE
    |
    \0\0\376\377   # UTF-32BE
    |
    \376\377       # UTF-16BE
    |
    \377\376       # UTF-16LE
    )
/x;

# Unicode encoding detection
my $UTF_PATTERNS = {
    "\0\0\0[^\0]"    => 'UTF-32BE',
    "\0[^\0]\0[^\0]" => 'UTF-16BE',
    "[^\0]\0\0\0"    => 'UTF-32LE',
    "[^\0]\0[^\0]\0" => 'UTF-16LE'
};

# Hey...That's not the wallet inspector...
sub decode {
    my ($self, $string) = @_;

    # Shortcut
    return unless $string;

    # Cleanup
    $self->error(undef);

    # Remove BOM
    $string =~ s/^$BOM_RE//go;

    # Detect and decode unicode
    my $encoding = 'UTF-8';
    for my $pattern (keys %$UTF_PATTERNS) {
        if ($string =~ /^$pattern/) {
            $encoding = $UTF_PATTERNS->{$pattern};
            last;
        }
    }
    $string = b($string)->decode($encoding)->to_string;

    # Decode
    my $result = $self->_decode_structure(\$string);

    # Exception
    return if $self->error;

    # Bad input
    $self->error('JSON text has to be a serialized object or array.')
      and return
      unless ref $result->[0];

    # Done
    return $result->[0];
}

sub encode {
    my ($self, $ref) = @_;

    # Encode
    my $string = $self->_encode_values($ref);

    # Unicode
    return b($string)->encode('UTF-8')->to_string;
}

sub false {$FALSE}

sub true {$TRUE}

sub _decode_array {
    my ($self, $ref) = @_;

    # New array
    my $array = [];

    # Decode array
    while ($$ref) {

        # Separator
        next if $$ref =~ s/$VALUE_SEPARATOR_RE//o;

        # End
        return $array if $$ref =~ s/$ARRAY_END_RE//o;

        # Value
        if (my $values = $self->_decode_values($ref)) {
            push @$array, @$values;
        }

        # Invalid format
        else { return $self->_exception($ref) }

    }

    # Exception
    return $self->_exception($ref, 'Missing right square bracket');
}

sub _decode_names {
    my ($self, $ref) = @_;

    # Name found
    if ($$ref =~ s/$NAMES_RE//o) { return $1 }

    # No number
    return;
}

sub _decode_number {
    my ($self, $ref) = @_;

    # Number found
    if ($$ref =~ s/$NUMBER_RE//o) { return $1 }

    # No number
    return;
}

sub _decode_object {
    my ($self, $ref) = @_;

    # New object
    my $hash = {};

    # Decode object
    my $key;
    while ($$ref) {

        # Name separator
        next if $$ref =~ s/$NAME_SEPARATOR_RE//o;

        # Value separator
        next if $$ref =~ s/$VALUE_SEPARATOR_RE//o;

        # End
        return $hash if $$ref =~ s/$OBJECT_END_RE//o;

        # Value
        if (my $values = $self->_decode_values($ref)) {

            # Value
            if ($key) {
                $hash->{$key} = $values->[0];
                $key = undef;
            }

            # Key
            else { $key = $values->[0] }

        }

        # Invalid format
        else { return $self->_exception($ref) }

    }

    # Exception
    return $self->_exception($ref, 'Missing right curly bracket');
}

sub _decode_string {
    my ($self, $ref) = @_;

    # String
    if ($$ref =~ s/$STRING_RE//o) {
        my $string = $1;

        # Unescape
        $string =~ s/$UNESCAPE_RE/_unescape($1, $2, $3, $4)/gex;

        return $string;
    }

    # No string
    return;
}

sub _decode_structure {
    my ($self, $ref) = @_;

    # Shortcut
    return unless $$ref;

    # Object
    if ($$ref =~ s/$OBJECT_BEGIN_RE//o) {
        return [$self->_decode_object($ref)];
    }

    # Array
    elsif ($$ref =~ s/$ARRAY_BEGIN_RE//o) {
        return [$self->_decode_array($ref)];
    }

    # Nothing
    return;
}

sub _decode_values {
    my ($self, $ref) = @_;

    # Number
    if (defined(my $number = $self->_decode_number($ref))) {
        return [$number];
    }

    # String
    elsif (defined(my $string = $self->_decode_string($ref))) {
        return [$string];
    }

    # Name
    elsif (my $name = $self->_decode_names($ref)) {

        # "false"
        if ($name eq 'false') { $name = $FALSE }

        # "null"
        elsif ($name eq 'null') { $name = undef }

        # "true"
        elsif ($name eq 'true') { $name = $TRUE }

        return [$name];
    }

    # Object or array
    return $self->_decode_structure($ref);
}

sub _encode_array {
    my ($self, $array) = @_;

    # Values
    my @array;
    for my $value (@$array) {
        push @array, $self->_encode_values($value);
    }

    # Stringify
    my $string = join ',', @array;
    return "[$string]";
}

sub _encode_object {
    my ($self, $object) = @_;

    # Values
    my @values;
    for my $key (keys %$object) {
        my $name  = $self->_encode_string($key);
        my $value = $self->_encode_values($object->{$key});
        push @values, "$name:$value";
    }

    # Stringify
    my $string = join ',', @values;
    return "{$string}";
}

sub _encode_string {
    my ($self, $string) = @_;

    # Escape
    $string =~ s/$ESCAPE_RE/_escape($1, $2)/gex;

    # Stringify
    return "\"$string\"";
}

sub _encode_values {
    my ($self, $value) = @_;

    # Reference
    if (my $ref = ref $value) {

        # Array
        return $self->_encode_array($value) if $ref eq 'ARRAY';

        # Object
        return $self->_encode_object($value) if $ref eq 'HASH';
    }

    # "null"
    return 'null' unless defined $value;

    # "false"
    return 'false' if ref $value eq 'Mojo::JSON::_Bool' && !$value;

    # "true"
    return 'true' if ref $value eq 'Mojo::JSON::_Bool' && $value;

    # Number
    return $value if $value =~ m/$NUMBER_RE$/o;

    # String
    return $self->_encode_string($value);
}

sub _escape {
    my ($special, $control) = @_;

    # Special character
    if ($special) { return $REVERSE_ESCAPE->{$special} }

    # Control character
    elsif ($control) { return '\\u00' . unpack('H2', $control) }

    return;
}

sub _unescape {
    my ($special, $high, $low, $normal) = @_;

    # Special character
    if ($special) { return $ESCAPE->{$special} }

    # Normal unicode character
    elsif ($normal) { return pack('U', hex($normal)) }

    # Surrogate pair
    elsif ($high && $low) {
        return pack('U*',
            (0x10000 + (hex($high) - 0xD800) * 0x400 + (hex($low) - 0xDC00)));
    }

    return;
}

sub _exception {
    my ($self, $ref, $error) = @_;

    # Message
    $error ||= 'Syntax error';

    # Context
    my $context = substr $$ref, 0, 25;
    $context = "\"$context\"" if $context;
    $context ||= 'end of file';

    # Error
    $self->error(qq/$error near $context./) and return;
}

# Emulate boolean type
package Mojo::JSON::_Bool;

use strict;
use warnings;

use base 'Mojo::Base';
use overload (
    '0+' => sub { $_[0]->{_value} },
    '""' => sub { $_[0]->{_value} }
);

sub new { shift->SUPER::new(_value => shift) }

1;
__END__

=head1 NAME

Mojo::JSON - Minimalistic JSON

=head1 SYNOPSIS

    use Mojo::JSON;

    my $json   = Mojo::JSON->new;
    my $string = $json->encode({foo => [1, 2], bar => 'hello!'});
    my $hash   = $json->decode('{"foo": [3, -2, 1]}');

=head1 DESCRIPTION

L<Mojo::JSON> is a minimalistic and relaxed implementation of RFC4627.

It supports normal Perl data types like C<Scalar>, C<Array> and C<Hash>, but
not blessed references.

    [1, -2, 3]     -> [1, -2, 3]
    {"foo": "bar"} -> {foo => 'bar'}

Literal names will be translated to and from L<Mojo::JSON> constants or a
similar native Perl value.

    true  -> Mojo::JSON->true
    false -> Mojo::JSON->false
    null  -> undef

Decoding UTF-16 (LE/BE) and UTF-32 (LE/BE) will be handled transparently,
encoding will only generate UTF-8.

=head1 ATTRIBUTES

L<Mojo::JSON> implements the following attributes.

=head2 C<error>

    my $error = $json->error;
    $json     = $json->error('Oops!');

Parser errors.

=head1 METHODS

L<Mojo::JSON> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<decode>

    my $array = $json->decode('[1, 2, 3]');
    my $hash  = $json->decode('{"foo": "bar"}');

Decode JSON string.

=head2 C<encode>

    my $string = $json->encode({foo => 'bar'});

Encode Perl structure.

=head2 C<false>

    my $false = Mojo::JSON->false;
    my $false = $json->false;

False value, used because Perl has no native equivalent.

=head2 C<true>

    my $true = Mojo::JSON->true;
    my $true = $json->true;

True value, used because Perl has no native equivalent.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
