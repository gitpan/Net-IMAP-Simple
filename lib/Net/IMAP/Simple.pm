package Net::IMAP::Simple;
# $Id: Simple.pm,v 1.3 2004/06/29 12:00:06 cwest Exp $
use strict;
use IO::Socket;
use IO::File;

use vars qw[$VERSION];
$VERSION = '0.95';

=head1 NAME

Net::IMAP::Simple - Perl extension for simple IMAP account handling.

=head1 SYNOPSIS

    use Net::IMAP::Simple;
    use Email::Simple;

    my $server = Net::IMAP::Simple->new( 'someserver' );
    $server->login( 'someuser', 'somepassword' );
    
    my $nmessages = $server->select( 'somefolder' );

    foreach my $msg ( 1 .. $number_of_messages ) {
        print "This message has been read before...\n"
          if $server->seen( $msg );

        my $email = Email::Simple->new( join '', @{$server->get( $msg )} );
        
        print $email->header('Subject'), "\n";
    }

    $server->quit();

=head1 DESCRIPTION

This module is a simple way to access IMAP accounts.

=head2 Methods

=over 4

=item new

  my $imap = Net::IMAP::Simple->new( $server );

This class method constructs a new C<Net::IMAP::Simple> object. It takes
one required parameter, the server to connect to. The parameter may
specify just the server, or both the server and port number. To specify
an alternate port, seperate it from the server with a colon (C<:>),
C<example.com:5143>.

On success an object is returned. On failure, C<undef> is returned.

=cut

sub new {
    my ( $class, $server) = @_;

    my $self = bless {
        count => -1,
    } => $class;
    
    my $connect  = $server;
       $connect .= ':' . $self->_port if index($connect, ':') == -1;

    $self->{sock} = $self->_sock_from->new( $connect )
        or return;
    $self->_sock->getline();

    return $self;
}
sub _port         { 143                }
sub _sock_from    { 'IO::Socket::INET' }
sub _sock         { $_[0]->{sock}      }
sub _count        { $_[0]->{count}     }
sub _last         { $_[0]->{last}      }

=pod

=item login

  my $inbox_msgs = $imap->login($user => $passwd);

This method takes two required parameters, a username and password. This pair
is authenticated against the server. If authentication is successful the
user's INBOX is selected.

On success, the number of messages in the INBOX is returned. C<undef> is returned
on failure.

=cut

sub login {
    my ( $self, $user, $pass ) = @_;

    $self->_process_cmd(
        cmd     => [LOGIN => qq[$user "$pass"]],
        final   => sub { $self->select('INBOX') },
        process => sub { },
    );
}

=pod

=item select

    my $num_messages = $imap->select($folder);

Selects a folder named in the single required parameter. The number of messages
in that folder is returned on success. On failure, C<undef> is returned.

=cut

sub select {
    my ( $self, $mbox ) = @_;

    my $messages;
    $self->_process_cmd(
        cmd     => [SELECT => _escape($mbox)],
        final   => sub { $self->{last} = $messages },
        process => sub { if ($_[0] =~ /^\*\s+(\d+)\s+EXISTS/i) { $messages = $1 } },
    );
}

=pod

=item top

    my $header = $imap->top( $message_number );
    print for @{$header};

This method accepts a message number as its required parameter. That message
will be retrieved from the currently selected folder. On success this method
returns a list reference containing the lines of the header. C<undef> is
returned on failure.

=cut

sub top {
    my ( $self, $number ) = @_;
    
    my @lines;
    $self->_process_cmd(
        cmd     => [FETCH => qq[$number rfc822.header]],
        final   => sub { \@lines },
        process => sub { push @lines, $_[0] if $_[0] =~ /^[^:]+:/ },
    );
}

=pod

=item seen

  print "Seen it!" if $imap->seen( $message_number );

A message number is the only required parameter for this method. The message's
C<\Seen> flag will be examined and if the message has been seen a true
value is returned. All other failures return a false value.

=cut

sub seen {
    my ( $self, $number ) = @_;
    
    my $lines = '';
    $self->_process_cmd(
        cmd     => [FETCH=> qq[$number (FLAGS)]],
        final   => sub { $lines =~ /\\Seen/i },
        process => sub { $lines .= $_[0] },
    );
}

=pod

=item list

  my $message_size  = $imap->list($message_number);
  my $mailbox_sizes = $imap->list;

This method returns size information for a message, as indicated in the
single optional parameter, or all messages in a mailbox. When querying a
single message a scalar value is returned. When listing the entire
mailbox a hash is returned. On failure, C<undef> is returned.

=cut

sub list {
    my ( $self, $number ) = @_;

    my $messages = $number || '1:' . $self->_last;
    my %list;
    $self->_process_cmd(
        cmd     => [FETCH => qq[$messages RFC822.SIZE]],
        final   => sub { $number ? $list{$number} : \%list },
        process => sub {
                        if ($_[0] =~ /^\*\s+(\d+).*RFC822.SIZE\s+(\d+)/i) {
                            $list{$1} = $2;
                        }
                       },
    );
}

=pod

=item get

  my $message = $imap->get( $message_number );
  print for @{$message};

This method fetches a message and returns its lines in a list reference.
On failure, C<undef> is returned.

=cut

sub get {
    my ( $self, $number ) = @_;

    my @lines;
    $self->_process_cmd(
        cmd     => [FETCH => qq[$number rfc822]],
        final   => sub { pop @lines; \@lines },
        process => sub { push @lines, $_[0] unless $_[0] =~ /^\*/ },
    );

}

=pod

=item getfh

  my $file = $imap->getfh( $message_number );
  print <$file>;

On success this method returns a file handle pointing to the message
identified by the required parameter. On failure, C<undef> is returned.

=cut

sub getfh {
    my ( $self, $number ) = @_;
    
    my $file = IO::File->new_tmpfile;
    my $buffer;
    $self->_process_cmd(
        cmd     => [FETCH => qq[$number rfc822]],
        final   => sub { seek $file, 0, 0; $file },
        process => sub {
                        defined($buffer) and print $file $buffer unless /^\*/;
                        $buffer = $_[0];
                       },
    );
}

=pod

=item quit

  $item->quit;

This method logs out of the IMAP server, expunges the selected mailbox,
and closes the connection.

=cut

sub quit {
    my ( $self ) = @_;
    $self->_send_cmd('EXPUNGE');
    $self->_send_cmd('LOGOUT');
    $self->_sock->close;
    return 1;
}    

=pod

=item last

  my $message_number = $imap->last;

This method retuns the message number of the last message in the selected
mailbox, since the last time the mailbox was selected. On failure, C<undef>
is returned.

=cut

sub last { shift->_last }

=pod

=item delete

  print "Gone!" if $imap->delete( $message_number );

This method deletes a message from the selected mailbox. On success it
returns true. False on failure.

=cut

sub delete {
    my ( $self, $number ) = @_;
    
    $self->_process_cmd(
        cmd     => [STORE => qq[$number +FLAGS (\\Deleted)]],
        final   => sub { 1 },
        process => sub { },
    );
}

sub _process_list {
    my ($self, $line) = @_;
    my @list;
    if ( $line =~ /^\*\s+LIST.*\s+\{\d+\}\s*$/i ) {
        chomp( my $res = $self->_sock->getline );
        $res =~ s/\r//;
        _escape($res);
        push @list, $res;
    } elsif ( $line =~ /^\*\s+LIST.*\s+(\".*?\")\s*$/i ||
              $line =~ /^\*\s+LIST.*\s+(\S+)\s*$/i ) {
        push @list, $1;
    }
    @list;
}

=pod

=item mailboxes

  my @boxes   = $imap->mailboxes;
  my @folders = $imap->mailboxes("Mail/%");
  my @lists   = $imap->mailboxes("lists/perl/*", "/Mail/");

This method returns a list of mailboxes. When called with no arguments it
recurses from the IMAP root to get all mailboxes. The first optional
argument is a mailbox path and the second is the path reference. RFC 3501
has more information.

=cut

sub mailboxes {
    my ( $self, $box, $ref ) = @_;
    
    $ref ||= '""';
    my @list;
    if ( ! defined $box ) {
        # recurse, should probably follow
        # RFC 2683: 3.2.1.1.  Listing Mailboxes
        return $self->_process_cmd(
            cmd     => [LIST => qq[$ref *]],
            final   => sub { _unescape($_) for @list; @list },
            process => sub { push @list, $self->_process_list($_[0]) },
        );
    } else {
        return $self->_process_cmd(
            cmd     => [LIST => qq[$ref $box]],
            final   => sub { _unescape($_) for @list; @list },
            process => sub { push @list, $self->_process_list($_[0]) },
        );
    }
}

=pod

=item create_mailbox

  print "Created" if $imap->create_mailbox( "/Mail/lists/perl/advocacy" );

This method creates the mailbox named in the required argument. Returns true
on success, false on failure.

=cut

sub create_mailbox {
    my ( $self, $box ) = @_;
    _escape( $box );
    
    return $self->_process_cmd(
        cmd     => [CREATE => $box],
        final   => sub { 1 },
        process => sub { },
    );
}

=pod

=item expunge_mailbox

  print "Expunged" if $imap->expunge_mailbox( "/Mail/lists/perl/advocacy" );

This method removes all mail marked as deleted in the mailbox named in
the required argument. Returns true on success, false on failure.

=cut

sub expunge_mailbox {
    my ( $self, $box ) = @_;
    _escape( $box );
    
    return $self->_process_cmd(
        cmd     => [EXPUNGE => $box],
        final   => sub { 1 },
        process => sub { },
    );
}

=pod

=item delete_mailbox

  print "Deleted" if $imap->delete_mailbox( "/Mail/lists/perl/advocacy" );

This method deletes the mailbox named in the required argument. Returns true
on success, false on failure.

=cut

sub delete_mailbox {
    my ( $self, $box ) = @_;
    _escape( $box );
    
    return $self->_process_cmd(
        cmd     => [DELETE => $box],
        final   => sub { 1 },
        process => sub { },
    );
}

=pod

=item rename_mailbox

  print "Renamed" if $imap->rename_mailbox( $old => $new );

This method renames the mailbox in the first required argument to the
mailbox named in the second required argument. Returns true on success,
false on failure.

=cut

sub rename_mailbox {
    my ( $self, $old_box, $new_box ) = @_;
    _escape( $old_box );
    _escape( $new_box );
    
    return $self->_process_cmd(
        cmd     => [RENAME => qq[$old_box $new_box]],
        final   => sub { 1 },
        process => sub { },
    );
}

=pod

=item copy

  print "copied" if $imap->copy( $message_number, $mailbox );

This method copies the message number in the currently seleted mailbox to
the fold specified in the second argument. Both arguments are required. On
success this method returns true. Returns false on failure.

=cut

sub copy {
    my ( $self, $number, $box ) = @_;
    _escape( $box );
    
    return $self->_process_cmd(
        cmd     => [COPY => qq[$number $box]],
        final   => sub { 1 },
        process => sub { },
    );
}

sub _nextid       { ++$_[0]->{count}   }
sub _escape {
    $_[0] =~ s/\\/\\\\/g;
    $_[0] =~ s/\"/\\\"/g;
    $_[0] = "\"$_[0]\"";
}
sub _unescape {
    $_[0] =~ s/^"//g;
    $_[0] =~ s/"$//g;
    $_[0] =~ s/\\\"/\"/g;
    $_[0] =~ s/\\\\/\\/g;
}
sub _send_cmd {
    my ( $self, $name, $value ) = @_;
    my $sock = $self->_sock;
    my $id   = $self->_nextid;
    my $cmd  = qq[$id $name $value\r\n];
    { local $\; print $sock $cmd; }
    return ($sock => $id);
}
sub _cmd_ok {
    my ($self, $res) = @_;
    my $id = $self->_count;
    return 1 if $res =~ /^$id\s+OK/i;
    return 0 if $res =~ /^$id\s+(?:NO|BAD)/i;
    return undef;
}
sub _process_cmd {
    my ($self, %args) = @_;
    my ($sock, $id) = $self->_send_cmd(@{$args{cmd}});

    my $res;
    while ( $res = $sock->getline ) {
        my $ok = $self->_cmd_ok($res);
        if ( $ok == 1 ) {
            return $args{final}->($res);
        } elsif ( defined($ok) && ! $ok ) {
            return;
        } else {
            $args{process}->($res);
        }
    }
}

=pod

=back

=cut

1;

__END__

=head1 AUTHOR

Casey West, <F<casey@geeknst.com>>.

Joao Fonseca, <F<joao_g_fonseca@yahoo.com>>.

=head1 SEE ALSO

L<Net::IMAP>,
L<perl>.

=head1 COPYRIGHT

Copyright (c) 2004 Casey West.
Copyright (c) 1999 Joao Fonseca.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl
itself.

=cut

