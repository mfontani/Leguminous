package Mojo::Transaction;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';

__PACKAGE__->attr([qw/connection kept_alive local_address local_port/]);
__PACKAGE__->attr([qw/previous remote_port/]);
__PACKAGE__->attr(
    [qw/finished resume_cb/] => sub {
        sub {1}
    }
);
__PACKAGE__->attr(keep_alive => 0);

# Please don't eat me! I have a wife and kids. Eat them!
sub client_read  { croak 'Method "client_read" not implemented by subclass' }
sub client_write { croak 'Method "client_write" not implemented by subclass' }

sub error {
    my $self = shift;
    my $req  = $self->req;
    return $req->error if $req->error;
    my $res = $self->res;
    return $res->error if $res->error;
    return;
}

sub is_done {
    return 1 if (shift->{_state} || '') eq 'done';
    return;
}

sub is_paused {
    return 1 if (shift->{_state} || '') eq 'paused';
    return;
}

sub is_websocket {0}

sub is_writing {
    return 1 unless my $state = shift->{_state};
    return 1
      if $state eq 'write'
          || $state eq 'write_start_line'
          || $state eq 'write_headers'
          || $state eq 'write_body';
    return;
}

sub pause {
    my $self = shift;

    # Already paused
    return $self if $self->{_real_state};

    # Save state
    $self->{_real_state} = $self->{_state};

    # Pause
    $self->{_state} = 'paused';

    return $self;
}

sub remote_address {
    my ($self, $address) = @_;

    # Set
    if ($address) {
        $self->{remote_address} = $address;

        # Activate reverse proxy support for local requests
        $ENV{MOJO_REVERSE_PROXY} ||= 1 if $address eq '127.0.0.1';

        return $self;
    }

    # Reverse proxy
    if ($ENV{MOJO_REVERSE_PROXY}) {

        # Forwarded
        my $forwarded = $self->{_forwarded_for};
        return $forwarded if $forwarded;

        # Reverse proxy
        if ($forwarded = $self->req->headers->header('X-Forwarded-For')) {

            # Real address
            if ($forwarded =~ /([^,\s]+)$/) {
                $self->{_forwarded_for} = $1;
                return $1;
            }
        }
    }

    # Get
    return $self->{remote_address};
}

sub req { croak 'Method "req" not implemented by subclass' }
sub res { croak 'Method "res" not implemented by subclass' }

sub resume {
    my $self = shift;

    # Not paused
    return unless $self->{_real_state};

    # Resume
    $self->{_state} = delete $self->{_real_state};

    # Callback
    $self->resume_cb->($self);

    return $self;
}

sub server_close {
    my $self = shift;

    # Transaction finished
    $self->finished->($self);

    return $self;
}

sub server_read  { croak 'Method "server_read" not implemented by subclass' }
sub server_write { croak 'Method "server_write" not implemented by subclass' }

sub success {
    my $self = shift;
    return $self->res unless $self->error;
    return;
}

1;
__END__

=head1 NAME

Mojo::Transaction - Transaction Base Class

=head1 SYNOPSIS

    use base 'Mojo::Transaction';

=head1 DESCRIPTION

L<Mojo::Transaction> is an abstract base class for transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction> implements the following attributes.

=head2 C<connection>

    my $connection = $tx->connection;
    $tx            = $tx->connection($connection);

Connection identifier or socket.

=head2 C<finished>

    my $cb = $tx->finished;
    $tx    = $tx->finished(sub {...});

Callback signaling that the transaction has been finished.

    $tx->finsihed(sub {
        my $self = shift;
    });

=head2 C<keep_alive>

    my $keep_alive = $tx->keep_alive;
    $tx            = $tx->keep_alive(1);

Connection can be kept alive.

=head2 C<kept_alive>

    my $kept_alive = $tx->kept_alive;
    $tx            = $tx->kept_alive(1);

Connection has been kept alive.

=head2 C<local_address>

    my $local_address = $tx->local_address;
    $tx               = $tx->local_address($address);

Local interface address.

=head2 C<local_port>

    my $local_port = $tx->local_port;
    $tx            = $tx->local_port($port);

Local interface port.

=head2 C<previous>

    my $previous = $tx->previous;
    $tx          = $tx->previous(Mojo::Transaction->new);

Previous transaction that triggered this followup transaction.

=head2 C<remote_address>

    my $remote_address = $tx->remote_address;
    $tx                = $tx->remote_address($address);

Remote interface address.

=head2 C<remote_port>

    my $remote_port = $tx->remote_port;
    $tx             = $tx->remote_port($port);

Remote interface port.

=head2 C<resume_cb>

    my $cb = $tx->resume_cb;
    $tx    = $tx->resume_cb(sub {...});

Callback to be invoked whenever the transaction is resumed.

=head1 METHODS

L<Mojo::Transaction> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<client_read>

    $tx = $tx->client_read($chunk);

Read and process client data.

=head2 C<client_write>

    my $chunk = $tx->client_write;

Write client data.

=head2 C<error>

    my $message          = $message->error;
    my ($message, $code) = $message->error;

Parser errors and codes.

=head2 C<is_done>

    my $done = $tx->is_done;

Check if transaction is done.

=head2 C<is_paused>

    my $paused = $tx->is_paused;

Check if transaction is paused.

=head2 C<is_websocket>

    my $is_websocket = $tx->is_websocket;

Check if transaction is a WebSocket.

=head2 C<is_writing>

    my $writing = $tx->is_writing;

Check if transaction is writing.

=head2 C<pause>

    $tx = $tx->pause;

Pause transaction, it can still read but writing is disabled while paused.

=head2 C<req>

    my $req = $tx->req;

Transaction request.

=head2 C<res>

    my $res = $tx->res;

Transaction response.

=head2 C<resume>

    $tx = $tx->resume;

Resume transaction.

=head2 C<server_close>

    $tx = $tx->server_close;

Transaction closed.

=head2 C<server_read>

    $tx = $tx->server_read($chunk);

Read and process server data.

=head2 C<server_write>

    my $chunk = $tx->server_write;

Write server data.

=head2 C<success>

    my $res = $tx->success;

Returns the L<Mojo::Message::Response> object (C<res>) if transaction was
successful or C<undef> otherwise.
Connection and parser errors have only a message in C<error>, 400 and 500
responses also a code.
Note that this method is EXPERIMENTAL and might change without warning!

    if (my $res = $tx->success) {
        print $res->body;
    }
    else {
        my ($message, $code) = $tx->error;
        if ($code) {
            print "$code $message response.\n";
        }
        else {
            print "Connection error: $message\n";
        }
    }

Error messages can be accessed with the C<error> method of the transaction
object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
