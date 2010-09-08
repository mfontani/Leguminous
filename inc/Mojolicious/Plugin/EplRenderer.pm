package Mojolicious::Plugin::EplRenderer;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::Template;

# Clever things make people feel stupid and unexpected things make them feel
# scared.
sub register {
    my ($self, $app) = @_;

    # Add "epl" handler
    $app->renderer->add_handler(
        epl => sub {
            my ($r, $c, $output, $options) = @_;

            # Template
            return unless my $t    = $r->template_name($options);
            return unless my $path = $r->template_path($options);
            my $cache = delete $options->{cache} || $path;

            # Reload
            delete $r->{_epl_cache} if $ENV{MOJO_RELOAD};

            # Check cache
            $r->{_epl_cache} ||= {};
            my $mt = $r->{_epl_cache}->{$cache};

            # Interpret again
            if ($mt && $mt->compiled) { $$output = $mt->interpret($c) }

            # No cache
            else {

                # Initialize
                $mt ||= Mojo::Template->new;

                # Encoding
                $mt->encoding($r->encoding) if $r->encoding;

                # Try template
                if (-r $path) { $$output = $mt->render_file($path, $c) }

                # Try DATA section
                elsif (my $d = $r->get_inline_template($options, $t)) {
                    $$output = $mt->render($d, $c);
                }

                # No template
                else {
                    $c->render_not_found($t);
                    return;
                }

                # Cache
                $r->{_epl_cache}->{$cache} = $mt;
            }

            # Exception
            if (ref $$output) {
                my $e = $$output;
                $$output = '';
                $c->render_exception($e);
            }

            # Success or exception
            return ref $$output ? 0 : 1;
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::EplRenderer - EPL Renderer Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('epl_renderer');

    # Mojolicious::Lite
    plugin 'epl_renderer';

=head1 DESCRIPTION

L<Mojolicous::Plugin::EplRenderer> is a renderer for C<epl> templates.
C<epl> templates are pretty much just raw L<Mojo::Template>.

=head1 METHODS

L<Mojolicious::Plugin::EplRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
