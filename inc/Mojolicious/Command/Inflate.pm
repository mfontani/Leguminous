package Mojolicious::Command::Inflate;

use strict;
use warnings;

use base 'Mojo::Command';

use Getopt::Long 'GetOptions';
use Mojo::Loader;

__PACKAGE__->attr(description => <<'EOF');
Inflate embedded files to real files.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 inflate [OPTIONS]
  --class <class>      Class to inflate.
  --public <path>      Path prefix for generated static files, defaults to
                       public.
  --templates <path>   Path prefix for generated template files, defaults to
                       templates.
EOF

# Eternity with nerds. It's the Pasadena Star Trek convention all over again.
sub run {
    my $self = shift;

    # Class
    my $class     = 'main';
    my $public    = 'public';
    my $templates = 'templates';

    # Options
    local @ARGV = @_ if @_;
    GetOptions(
        'class=s'     => sub { $class     = $_[1] },
        'public=s'    => sub { $public    = $_[1] },
        'templates=s' => sub { $templates = $_[1] },
    );

    # Load class
    my $e = Mojo::Loader->load($class);
    die $e if ref $e;

    # Generate
    my $all = $self->get_all_data($class);
    for my $file (keys %$all) {
        my $prefix = $file =~ /\.\w+\.\w+$/ ? $templates : $public;
        my $path = $self->rel_file("$prefix/$file");
        $self->write_file($path, $all->{$file});
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Inflate - Inflate Command

=head1 SYNOPSIS

    use Mojolicious::Command::Inflate;

    my $inflate = Mojolicious::Command::Inflate->new;
    $inflate->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Inflate> prints all your application routes.

=head1 ATTRIBUTES

L<Mojolicious::Command::Inflate> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $inflate->description;
    $inflate        = $inflate->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $inflate->usage;
    $inflate  = $inflate->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Inflate> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $inflate = $inflate->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
