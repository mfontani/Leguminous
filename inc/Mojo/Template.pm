package Mojo::Template;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Encode qw/decode encode/;
use IO::File;
use Mojo::ByteStream;
use Mojo::Exception;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 262144;

__PACKAGE__->attr([qw/auto_escape compiled namespace/]);
__PACKAGE__->attr([qw/append code prepend/] => '');
__PACKAGE__->attr(capture_end               => '}');
__PACKAGE__->attr(capture_start             => '{');
__PACKAGE__->attr(comment_mark              => '#');
__PACKAGE__->attr(encoding                  => 'UTF-8');
__PACKAGE__->attr(escape_mark               => '=');
__PACKAGE__->attr(expression_mark           => '=');
__PACKAGE__->attr(line_start                => '%');
__PACKAGE__->attr(tag_start                 => '<%');
__PACKAGE__->attr(tag_end                   => '%>');
__PACKAGE__->attr(template                  => '');
__PACKAGE__->attr(tree => sub { [] });
__PACKAGE__->attr(trim_mark => '=');

# Helpers
my $HELPERS = <<'EOF';
no strict 'refs'; no warnings 'redefine';
sub block;
*block = sub { shift->(@_) };
sub escape;
*escape = sub {
    my $v = shift;
    ref $v && ref $v eq 'Mojo::ByteStream'
      ? "$v"
      : Mojo::ByteStream->new($v)->xml_escape->to_string;
};
use strict; use warnings;
EOF
$HELPERS =~ s/\n//g;

sub build {
    my $self = shift;

    # Compile
    my @lines;
    my $cpst;
    for my $line (@{$self->tree}) {

        # New line
        push @lines, '';
        for (my $j = 0; $j < @{$line}; $j += 2) {
            my $type  = $line->[$j];
            my $value = $line->[$j + 1];

            # Need to fix line ending
            $value ||= '';
            my $newline = chomp $value;

            # Capture end
            if ($type eq 'cpen') {

                # End block
                $lines[-1] .= 'return $_M }';

                # No following code
                my $next = $line->[$j + 3];
                $lines[-1] .= ';' if !defined $next || $next =~ /^\s*$/;
            }

            # Text
            if ($type eq 'text') {

                # Quote and fix line ending
                $value = quotemeta($value);
                $value .= '\n' if $newline;

                $lines[-1] .= "\$_M .= \"" . $value . "\";";
            }

            # Code
            if ($type eq 'code') { $lines[-1] .= "$value" }

            # Expression
            if ($type eq 'expr' || $type eq 'escp') {

                # Escaped
                my $a = $self->auto_escape;
                if (($type eq 'escp' && !$a) || ($type eq 'expr' && $a)) {
                    $lines[-1] .= "\$_M .= escape";
                    $lines[-1] .= " +$value" if length $value;
                }

                # Raw
                else { $lines[-1] .= "\$_M .= $value" }

                # Append semicolon
                $lines[-1] .= ';' unless $cpst;
            }

            # Capture started
            if ($cpst) {
                $lines[-1] .= $cpst;
                $cpst = undef;
            }

            # Capture start
            if ($type eq 'cpst') {

                # Start block
                $cpst = " sub { my \$_M = ''; ";
            }
        }
    }

    # Wrap
    my $prepend   = $self->prepend;
    my $append    = $self->append;
    my $namespace = $self->namespace || ref $self;
    $lines[0] ||= '';
    $lines[0] =
      "package $namespace; sub { my \$_M = ''; $HELPERS; $prepend; do {"
      . $lines[0];
    $lines[-1] .= qq/$append; \$_M; } };/;

    $self->code(join "\n", @lines);
    return $self;
}

sub compile {
    my $self = shift;

    # Shortcut
    my $code = $self->code;
    return unless $code;

    # Compile
    my $compiled = eval $code;

    # Exception
    return Mojo::Exception->new($@, $self->template)->verbose(1) if $@;

    $self->compiled($compiled);
    return;
}

sub interpret {
    my $self = shift;

    # Compile
    unless ($self->compiled) {
        my $e = $self->compile;

        # Exception
        return $e if ref $e;
    }
    my $compiled = $self->compiled;

    # Shortcut
    return unless $compiled;

    # Interpret
    my $output = eval { $compiled->(@_) };
    $output = Mojo::Exception->new($@, $self->template)->verbose(1) if $@;

    return $output;
}

# I am so smart! I am so smart! S-M-R-T! I mean S-M-A-R-T...
sub parse {
    my ($self, $tmpl) = @_;
    $self->template($tmpl);

    # Clean start
    delete $self->{tree};

    # Tags
    my $line_start    = quotemeta $self->line_start;
    my $tag_start     = quotemeta $self->tag_start;
    my $tag_end       = quotemeta $self->tag_end;
    my $cmnt          = quotemeta $self->comment_mark;
    my $escp          = quotemeta $self->escape_mark;
    my $expr          = quotemeta $self->expression_mark;
    my $trim          = quotemeta $self->trim_mark;
    my $capture_start = quotemeta $self->capture_start;
    my $capture_end   = quotemeta $self->capture_end;

    my $mixed_re = qr/
        (
        $tag_start$capture_start$expr$escp   # Escaped expression (start)
        |
        $tag_start$expr$escp                 # Escaped expression
        |
        $tag_start$capture_start$expr        # Expression (start)
        |
        $tag_start$expr                      # Expression
        |
        $tag_start$capture_end$cmnt          # Comment (end)
        |
        $tag_start$capture_start$cmnt        # Comment (start)
        |
        $tag_start$cmnt                      # Comment
        |
        $tag_start$capture_end               # Code (end)
        |
        $tag_start$capture_start             # Code (start)
        |
        $tag_start                           # Code
        |
        $trim$capture_start$tag_end          # Trim end (start)
        |
        $trim$tag_end                        # Trim end
        |
        $capture_start$tag_end               # End (start)
        |
        $tag_end                             # End
        )
    /x;

    # Capture regex
    my $token_capture_re =
      qr/^($tag_start|$tag_end)($capture_end|$capture_start)/;

    # Tag end regex
    my $end_re = qr/
        ^(
        $trim$capture_start$tag_end   # Trim end (start)
        )|(
        $capture_start$tag_end        # End (start)
        )|(
        $trim$tag_end                 # Trim end
        )|
        $tag_end                      # End
        $
    /x;

    # Tokenize
    my $state                = 'text';
    my $multiline_expression = 0;
    my @capture_token;
    my $trimming = 0;
    for my $line (split /\n/, $tmpl) {
        my @capture;

        # Perl line with capture end or start
        if ($line =~ /^$line_start($capture_end|$capture_start)/) {
            my $capture = $1;
            $line =~ s/^($line_start)$capture/$1/;
            @capture =
              ("\\$capture" eq $capture_end ? 'cpen' : 'cpst', undef);
        }

        # Perl line with return value that needs to be escaped
        if ($line =~ /^$line_start$expr$escp(.+)?$/) {
            push @{$self->tree}, [@capture, 'escp', $1];
            $multiline_expression = 0;
            next;
        }

        # Perl line with return value
        if ($line =~ /^$line_start$expr(.+)?$/) {
            push @{$self->tree}, [@capture, 'expr', $1];
            $multiline_expression = 0;
            next;
        }

        # Comment line, dummy token needed for line count
        if ($line =~ /^$line_start$cmnt(.+)?$/) {
            push @{$self->tree}, [@capture];
            $multiline_expression = 0;
            next;
        }

        # Perl line without return value
        if ($line =~ /^$line_start([^\>]{1}.*)?$/) {
            push @{$self->tree}, [@capture, 'code', $1];
            $multiline_expression = 0;
            next;
        }

        # Escaped line ending
        if ($line =~ /(\\+)$/) {
            my $length = length $1;

            # Newline escaped
            if ($length == 1) {
                $line =~ s/\\$//;
            }

            # Backslash escaped
            if ($length >= 2) {
                $line =~ s/\\\\$/\\/;
                $line .= "\n";
            }
        }

        # Normal line ending
        else { $line .= "\n" }

        # Mixed line
        my @token;
        for my $token (split /$mixed_re/, $line) {

            # Done trimming
            $trimming = 0 if $trimming && $state ne 'text';

            # Perl token with capture end or start
            if ($token =~ /$token_capture_re/) {
                my $tag     = quotemeta $1;
                my $capture = quotemeta $2;
                $token =~ s/^($tag)$capture/$1/;
                @capture_token =
                  ($capture eq $capture_end ? 'cpen' : 'cpst', undef);
            }

            # End
            if ($state ne 'text' && $token =~ /$end_re/) {

                # Capture start
                splice @token, -2, 0, 'cpst', undef if $1 || $2;

                # Trim previous text
                if ($1 || $3) {
                    $trimming = 1;

                    # Trim current line
                    unless ($self->_trim_line(\@token, 4)) {

                        # Trim previous lines
                        for my $l (reverse @{$self->tree}) {
                            last if $self->_trim_line($l);
                        }
                    }
                }

                # Back to business as usual
                $state                = 'text';
                $multiline_expression = 0;
            }

            # Code
            elsif ($token =~ /^$tag_start$/) { $state = 'code' }

            # Expression
            elsif ($token =~ /^$tag_start$expr$/) {
                $state = 'expr';
            }

            # Expression that needs to be escaped
            elsif ($token =~ /^$tag_start$expr$escp$/) {
                $state = 'escp';
            }

            # Comment
            elsif ($token =~ /^$tag_start$cmnt$/) { $state = 'cmnt' }

            # Value
            else {

                # Trimming
                if ($trimming) {
                    if ($token =~ s/^(\s+)//) {

                        # Convert whitespace text to line noise
                        push @token, 'code', $1;

                        # Done with trimming
                        $trimming = 0 if length $token;
                    }
                }

                # Comments are ignored
                next if $state eq 'cmnt';

                # Multiline expressions are a bit complicated,
                # only the first line can be compiled as 'expr'
                $state = 'code' if $multiline_expression;
                $multiline_expression = 1 if $state eq 'expr';

                # Store value
                push @token, @capture_token, $state, $token;
                @capture_token = ();
            }
        }
        push @{$self->tree}, \@token;
    }

    return $self;
}

sub render {
    my $self = shift;
    my $tmpl = shift;

    # Parse
    $self->parse($tmpl);

    # Build
    $self->build;

    # Compile
    my $e = $self->compile;
    return $e if $e;

    # Interpret
    return $self->interpret(@_);
}

sub render_file {
    my $self = shift;
    my $path = shift;

    # Open file
    my $file = IO::File->new;
    $file->open("< $path") or croak "Can't open template '$path': $!";

    # Slurp file
    my $tmpl = '';
    while ($file->sysread(my $buffer, CHUNK_SIZE, 0)) {
        $tmpl .= $buffer;
    }

    # Encoding
    $tmpl = decode($self->encoding, $tmpl) if $self->encoding;

    # Render
    return $self->render($tmpl, @_);
}

sub render_file_to_file {
    my $self  = shift;
    my $spath = shift;
    my $tpath = shift;

    # Render
    my $output = $self->render_file($spath, @_);

    # Exception
    return $output if ref $output;

    # Write to file
    return $self->_write_file($tpath, $output);
}

sub render_to_file {
    my $self = shift;
    my $tmpl = shift;
    my $path = shift;

    # Render
    my $output = $self->render($tmpl, @_);

    # Exception
    return $output if ref $output;

    # Write to file
    return $self->_write_file($path, $output);
}

sub _trim_line {
    my ($self, $line, $offset) = @_;

    # Walk line backwards
    $offset ||= 2;
    for (my $j = @$line - $offset; $j >= 0; $j -= 2) {

        # Skip capture
        next if $line->[$j] eq 'cpst' || $line->[$j] eq 'cpen';

        # Only trim text
        return 1 unless $line->[$j] eq 'text';

        # Trim
        my $value = $line->[$j + 1];
        if ($line->[$j + 1] =~ s/(\s+)$//) {

            # Value
            $value = $line->[$j + 1];

            # Convert whitespace text to line noise
            splice @$line, $j, 0, 'code', $1;
        }

        # Text left
        return 1 if length $value;
    }

    return;
}

sub _write_file {
    my ($self, $path, $output) = @_;

    # Open file
    my $file = IO::File->new;
    $file->open("> $path") or croak "Can't open file '$path': $!";

    # Encoding
    $output = encode($self->encoding, $output) if $self->encoding;

    # Write to file
    $file->syswrite($output) or croak "Can't write to file '$path': $!";

    return;
}

1;
__END__

=head1 NAME

Mojo::Template - Perlish Templates!

=head1 SYNOPSIS

    use Mojo::Template;
    my $mt = Mojo::Template->new;

    # Simple
    my $output = $mt->render(<<'EOF');
    <!doctype html><html>
        <head><title>Simple</title></head>
        <body>Time: <%= localtime(time) %></body>
    </html>
    EOF
    print $output;

    # More complicated
    my $output = $mt->render(<<'EOF', 23, 'foo bar');
    %= 5 * 5
    % my ($number, $text) = @_;
    test 123
    foo <% my $i = $number + 2; %>
    % for (1 .. 23) {
    * some text <%= $i++ %>
    % }
    EOF
    print $output;

=head1 DESCRIPTION

L<Mojo::Template> is a minimalistic and very Perl-ish template engine,
designed specifically for all those small tasks that come up during big
projects.
Like preprocessing a config file, generating text from heredocs and stuff
like that.

    <% Inline Perl %>
    <%= Perl expression, replaced with result %>
    <%== Perl expression, replaced with XML escaped result %>
    <%# Comment, useful for debugging %>
    % Perl line
    %= Perl expression line, replaced with result
    %== Perl expression line, replaced with XML escaped result
    %# Comment line, useful for debugging

Automatic escaping behavior can be reversed with the C<auto_escape>
attribute, this is the default in L<Mojolicious> C<.ep> templates for
example.

    <%= Perl expression, replaced with XML escaped result %>
    <%== Perl expression, replaced with result %>
    %= Perl expression line, replaced with XML escaped result
    %== Perl expression line, replaced with result

L<Mojo::ByteStream> objects are always excluded from automatic escaping.
Whitespace characters around tags can be trimmed with a special tag ending.

    <%= All whitespace characters around this expression will be trimmed =%>

You can capture whole template blocks for reuse later.

    <% my $block = {%>
        <% my $name = shift; =%>
        Hello <%= $name %>.
    <%}%>
    <%= $block->('Sebastian') %>
    <%= $block->('Sara') %>

    %{ my $block =
    % my $name = shift;
    Hello <%= $name %>.
    %}
    %= $block->('Baerbel')
    %= $block->('Wolfgang')

L<Mojo::Template> templates work just like Perl subs (actually they get
compiled to a Perl sub internally).
That means you can access arguments simply via C<@_>.

    % my ($foo, $bar) = @_;
    % my $x = shift;
    test 123 <%= $foo %>

Note that you can't escape L<Mojo::Template> tags, instead we just replace
them if necessary.

    my $mt = Mojo::Template->new;
    $mt->line_start('@@');
    $mt->tag_start('[@@');
    $mt->tag_end('@@]');
    $mt->expression_mark('&');
    $mt->escape_mark('&');
    my $output = $mt->render(<<'EOF', 23);
    @@ my $i = shift;
    <% no code just text [@@&& $i @@]
    EOF

There is only one case that we can escape with a backslash, and thats a
newline at the end of a template line.

   This is <%= 23 * 3 %> a\
   single line

If for some strange reason you absolutely need a backslash in front of a
newline you can escape the backslash with another backslash.

    % use Data::Dumper;
    This will\\
    result <%=  Dumper {foo => 'bar'} %>\\
    in multiple lines

Templates get compiled to Perl code internally, this can make debugging a bit
tricky.
But L<Mojo::Template> will return L<Mojo::Exception> objects that stringify
to error messages with context.

    Bareword "xx" not allowed while "strict subs" in use at template line 4.
    2: </head>
    3: <body>
    4: % my $i = 2; xx
    5: %= $i * 2
    6: </body>

L<Mojo::Template> does not support caching by itself, but you can easily
build a wrapper around it.

    # Compile and store code somewhere
    my $mt = Mojo::Template->new;
    $mt->parse($template);
    $mt->build;
    my $code = $mt->code;

    # Load code and template (template for debug trace only)
    $mt->template($template);
    $mt->code($code);
    $mt->compile;
    my $output = $mt->interpret(@arguments);

=head1 ATTRIBUTES

L<Mojo::Template> implements the following attributes.

=head2 C<auto_escape>

    my $auto_escape = $mt->auto_escape;
    $mt             = $mt->auto_escape(1);

Activate automatic XML escaping.

=head2 C<append>

    my $code = $mt->append;
    $mt      = $mt->append('warn "Processed template"');

Append Perl code to compiled template.

=head2 C<capture_end>

    my $capture_end = $mt->capture_end;
    $mt             = $mt->capture_end('}');

Character indicating the end of a capture block, defaults to C<}>.

    %{ $block =
        Some data!
    %}

=head2 C<capture_start>

    my $capture_start = $mt->capture_start;
    $mt               = $mt->capture_start('{');

Character indicating the start of a capture block, defaults to C<{>.

    <% my $block = {%>
        Some data!
    <%}%>

=head2 C<code>

    my $code = $mt->code;
    $mt      = $mt->code($code);

Compiled template code.

=head2 C<comment_mark>

    my $comment_mark = $mt->comment_mark;
    $mt              = $mt->comment_mark('#');

Character indicating the start of a comment, defaults to C<#>.

    <%# This is a comment %>

=head2 C<encoding>

    my $encoding = $mt->encoding;
    $mt          = $mt->encoding('UTF-8');

Encoding used for template files.

=head2 C<escape_mark>

    my $escape_mark = $mt->escape_mark;
    $mt             = $mt->escape_mark('=');

Character indicating the start of an escaped expression, defaults to C<=>.

    <%== $foo %>

=head2 C<expression_mark>

    my $expression_mark = $mt->expression_mark;
    $mt                 = $mt->expression_mark('=');

Character indicating the start of an expression, defaults to C<=>.

    <%= $foo %>

=head2 C<line_start>

    my $line_start = $mt->line_start;
    $mt            = $mt->line_start('%');

Character indicating the start of a code line, defaults to C<%>.

    % $foo = 23;

=head2 C<namespace>

    my $namespace = $mt->namespace;
    $mt           = $mt->namespace('main');

Namespace used to compile templates.

=head2 C<prepend>

    my $code = $mt->prepend;
    $mt      = $mt->prepend('my $self = shift;');

Prepend Perl code to compiled template.

=head2 C<tag_start>

    my $tag_start = $mt->tag_start;
    $mt           = $mt->tag_start('<%');

Characters indicating the start of a tag, defaults to C<E<lt>%>.

    <% $foo = 23; %>

=head2 C<tag_end>

    my $tag_end = $mt->tag_end;
    $mt         = $mt->tag_end('%>');

Characters indicating the end of a tag, defaults to C<%E<gt>>.

    <%= $foo %>

=head2 C<template>

    my $template = $mt->template;
    $mt          = $mt->template($template);

Raw template.

=head2 C<tree>

    my $tree = $mt->tree;
    $mt      = $mt->tree($tree);

Parsed tree.

=head2 C<trim_mark>

    my $trim_mark = $mt->trim_mark;
    $mt           = $mt->trim_mark('-');

Character activating automatic whitespace trimming, defaults to C<=>.

    <%= $foo =%>

=head1 METHODS

L<Mojo::Template> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $mt = Mojo::Template->new;

Construct a new L<Mojo::Template> object.

=head2 C<build>

    $mt = $mt->build;

Build template.

=head2 C<compile>

    my $exception = $mt->compile;

Compile template.

=head2 C<interpret>

    my $output = $mt->interpret;
    my $output = $mt->interpret(@arguments);

Interpret template.

=head2 C<parse>

    $mt = $mt->parse($template);

Parse template.

=head2 C<render>

    my $output = $mt->render($template);
    my $output = $mt->render($template, @arguments);

Render template.

=head2 C<render_file>

    my $output = $mt->render_file($template_file);
    my $output = $mt->render_file($template_file, @arguments);

Render template file.

=head2 C<render_file_to_file>

    my $exception = $mt->render_file_to_file($template_file, $output_file);
    my $exception = $mt->render_file_to_file(
        $template_file, $output_file, @arguments
    );

Render template file to a specific file.

=head2 C<render_to_file>

    my $exception = $mt->render_to_file($template, $output_file);
    my $exception = $mt->render_to_file(
        $template, $output_file, @arguments
    );

Render template to a specific file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
