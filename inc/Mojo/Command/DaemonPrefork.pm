package Mojo::Command::DaemonPrefork;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Server::Daemon::Prefork;

use Getopt::Long 'GetOptions';

__PACKAGE__->attr(description => <<'EOF');
Start application with preforking HTTP 1.1 backend.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 daemon_prefork [OPTIONS]

These options are available:
  --clients <number>             Set maximum number of concurrent clients per
                                 child, defaults to 1.
  --daemonize                    Daemonize parent.
  --group <name>                 Set group name for children.
  --idle <seconds>               Set time children can be idle without
                                 getting killed, defaults to 30.
  --interval <seconds>           Set interval for process maintainance,
                                 defaults to 15.
  --keepalive <seconds>          Set keep-alive timeout, defaults to 15.
  --keepaliverequests <number>   Set maximum number of requests per
                                 keep-alive connection, defaults to 100.
  --listen <locations>           Set a comma separated list of locations you
                                 want to listen on, defaults to http://*:3000.
  --lock <path>                  Set path to lock file, defaults to a random
                                 temporary file.
  --maxspare <number>            Set maximum amount of idle children,
                                 defaults to 10.
  --minspare <number>            Set minimum amount of idle children,
                                 defaults to 5.
  --pid <path>                   Set path to pid file, defaults to a random
                                 temporary file.
  --queue <size>                 Set listen queue size, defaults to
                                 SOMAXCONN.
  --reload                       Automatically reload application when the
                                 source code changes.
  --requests <number>            Set maximum number of requests a worker
                                 process is allowed to handle, defaults to
                                 1000.
  --servers <number>             Set maximum number of children, defaults to
                                 100.
  --start <number>               Set number of children to spawn at startup,
                                 defaults to 5.
  --user <name>                  Set user name for children.
  --websocket <seconds>          Set WebSocket timeout, defaults to 300.
EOF

# Dear Mr. President, there are too many states nowadays.
# Please eliminate three.
# P.S. I am not a crackpot.
sub run {
    my $self   = shift;
    my $daemon = Mojo::Server::Daemon::Prefork->new;

    # Options
    my $daemonize;
    local @ARGV = @_ if @_;
    GetOptions(
        'clients=i'   => sub { $daemon->max_clients($_[1]) },
        daemonize     => \$daemonize,
        'group=s'     => sub { $daemon->group($_[1]) },
        'idle=i'      => sub { $daemon->idle_timeout($_[1]) },
        'interval=i'  => sub { $daemon->cleanup_interval($_[1]) },
        'keepalive=i' => sub { $daemon->keep_alive_timeout($_[1]) },
        'keepaliverequests=i' =>
          sub { $daemon->max_keep_alive_requests($_[1]) },
        'listen=s'    => sub { $daemon->listen($_[1]) },
        'lock=s'      => sub { $daemon->lock_file($_[1]) },
        'maxspare=i'  => sub { $daemon->max_spare_servers($_[1]) },
        'minspare=i'  => sub { $daemon->min_spare_servers($_[1]) },
        'pid=s'       => sub { $daemon->pid_file($_[1]) },
        'queue=i'     => sub { $daemon->listen_queue_size($_[1]) },
        reload        => sub { $daemon->reload(1) },
        'requests=i'  => sub { $daemon->max_requests($_[1]) },
        'servers=i'   => sub { $daemon->max_servers($_[1]) },
        'start=i'     => sub { $daemon->start_servers($_[1]) },
        'user=s'      => sub { $daemon->user($_[1]) },
        'websocket=i' => sub { $daemon->websocket_timeout($_[1]) }
    );

    # Daemonize
    $daemon->daemonize if $daemonize;

    # Run
    $daemon->run;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Command::DaemonPrefork - Prefork Daemon Command

=head1 SYNOPSIS

    use Mojo::Command::Daemon::Prefork;

    my $daemon = Mojo::Command::Daemon::Prefork->new;
    $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Daemon::Prefork> is a command interface to
L<Mojo::Server::Daemon::Prefork>.

=head1 ATTRIBUTES

L<Mojo::Command::Daemon::Prefork> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $daemon->description;
    $daemon         = $daemon->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $daemon->usage;
    $daemon   = $daemon->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojo::Command::Daemon::Prefork> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $daemon = $daemon->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
