package Net::IMAP::Simple;

use strict;
use vars qw($VERSION);

$VERSION = '0.90';



use IO::Socket;






#############################################################################
#
#
#
#############################################################################

sub new {
    my ( $class, $server, %options ) = @_;
    my ( $self );

    if ( ref( $class ) ) {
        $class = ref( $class );
    }

    $self = { %options };
    $self->{count} = 0;
    $self->{sock} = new IO::Socket::INET( "$server:143" )
        or return;
    $self->{sock}->getline();

    bless $self, $class;
    return $self;
}





#############################################################################
#
#
#
#############################################################################

sub _nextid {
    my ( $self ) = @_;

    return $self->{count}++;
}





#############################################################################
#
#
#
#############################################################################

sub login {
    my ( $self, $user, $pass ) = @_;
    my ( $sh, $id, $resp );

    $sh = $self->{sock};
    $id = $self->_nextid();
    
    print $sh "$id LOGIN $user $pass\n";
    $resp = $sh->getline();

    if ( $resp =~ /^$id\s+OK/i ) {
        return $self->select( 'INBOX' );
    }

    return;

}





#############################################################################
#
#
#
#############################################################################

sub select {
    my ( $self, $mbox ) = @_;
    my ( $sh, $id, $resp, $nmsg );

    $sh = $self->{sock};
    $id = $self->_nextid();
    
    print $sh "$id SELECT $mbox\n";
    while ( $resp = $sh->getline() ) {
        if ( $resp =~ /^\*\s+(\d+)\s+EXISTS/i ) {
            $nmsg = $1;
        } elsif ( $resp =~ /^$id\s+(OK|NO|BAD)/i ) {
            last;
        }
    }

    if ( defined $nmsg && $resp =~ /$id\s+OK/i ) {
        $self->{last} = $nmsg;
        return $nmsg;
    }

    return;
}





#############################################################################
#
#
#
#############################################################################

sub top {
    my ( $self, $msgn ) = @_;
    my ( $sh, $id, $resp, $lines );

    $sh = $self->{sock};
    $id = $self->_nextid();
    
    print $sh "$id FETCH $msgn rfc822.header\n";

    while ( $resp = $sh->getline() ) {
        if ( $resp =~ /^\*/ ) {
            next;
        }
        if ( $resp =~ /^$id\s+(OK|NO|BAD)/i ) {
            last;
        }
        push @$lines, $resp;
    }

    if ( $resp =~ /$id\s+OK/i ) {
        pop @$lines;
        return $lines;
    }

    return;

}





#############################################################################
#
#
#
#############################################################################

sub list {
    my ( $self, $msgn ) = @_;
    my ( $sh, $id, $resp, $hash );

    $sh = $self->{sock};
    $id = $self->_nextid();

    if ( defined $msgn ) {
        print $sh "$id FETCH $msgn RFC822.SIZE\n";
    } else {
        print $sh "$id FETCH 1:$self->{last} RFC822.SIZE\n";
    }

    while ( $resp = $sh->getline() ) {
        if ( $resp =~ /^\*\s+(\d+).*RFC822.SIZE\s+(\d+)/i ) {
            $hash->{$1} = $2;
            next;
        }
        if ( $resp =~ /^$id\s+(OK|NO|BAD)/i ) {
            last;
        }
    }
    
    if ( $resp =~ /$id\s+OK/i ) {
        if ( defined $msgn ) {
            return $hash->{$msgn};
        } else {
            return $hash;
        }
    }

    return;
}





#############################################################################
#
#
#
#############################################################################

sub get {
    my ( $self, $msgn ) = @_;
    my ( $sh, $id, $resp, $lines );

    $sh = $self->{sock};
    $id = $self->_nextid();
    
    print $sh "$id FETCH $msgn rfc822\n";

    while ( $resp = $sh->getline() ) {
        if ( $resp =~ /^\*/ ) {
            next;
        }
        if ( $resp =~ /^$id\s+(OK|NO|BAD)/i ) {
            last;
        }
        push @$lines, $resp;
    }

    if ( $resp =~ /$id\s+OK/i ) {
        pop @$lines;
        return $lines;
    }

    return;

}





#############################################################################
#
#
#
#############################################################################

sub quit {
    my ( $self ) = @_;
    my ( $sh, $id );

    $sh = $self->{sock};
    $id = $self->_nextid();
    print $sh "$id EXPUNGE\n";

    $id = $self->_nextid();
    print $sh "$id LOGOUT\n";
    <$sh>;
    close $sh;

    return 1;
}    





#############################################################################
#
#
#
#############################################################################

sub last {
    my ( $self ) = @_;

    return $self->{last};

}





#############################################################################
#
#
#
#############################################################################

sub delete {
    my ( $self, $msgn ) = @_;
    my ( $sh, $id, $resp );

    $sh = $self->{sock};
    $id = $self->_nextid();

    print $sh "$id STORE $msgn +FLAGS (\\Deleted)\n";
    while ( ( $resp = $sh->getline() ) && $resp !~ /^$id\s+(OK|NO|BAD)/i ) {
        next;
    }
    if ( $resp =~ /^$id\s+OK/i ) {
        return 1;
    }
        
    return;

}





#############################################################################
#
#
#
#############################################################################

sub mailboxes {
    my ( $self ) = @_;
    my ( $sh, $id, $resp, @list );

    $sh = $self->{sock};
    $id = $self->_nextid();

    print $sh "$id LIST \"\" *\n";
    while ( $resp = $sh->getline() ) {
        if ( $resp =~ /^\*\s+LIST.*\s+(\S+)\s*$/i ) {
            push @list, $1;
        } elsif ( $resp =~ /^$id\s+(OK|NO|BAD)/i ) {
            last;
        }
    }

    if ( $resp =~ /^$id\s+OK/i ) {
        return @list;
    }

    return;
}





#############################################################################
#
#
#
#############################################################################

sub create_mailbox {
    my ( $self, $mbox_name ) = @_;
    my ( $sh, $id, $resp, @list );

    $sh = $self->{sock};
    $id = $self->_nextid();

    print $sh "$id CREATE $mbox_name\n";
    $resp = $sh->getline();

    if ( $resp =~ /^$id\s+OK/i ) {
        return 1;
    }

    return;
}





#############################################################################
#
#
#
#############################################################################

sub delete_mailbox {
    my ( $self, $mbox_name ) = @_;
    my ( $sh, $id, $resp, @list );

    $sh = $self->{sock};
    $id = $self->_nextid();

    print $sh "$id DELETE $mbox_name\n";
    $resp = $sh->getline();

    if ( $resp =~ /^$id\s+OK/i ) {
        return 1;
    }

    return;
}





#############################################################################
#
#
#
#############################################################################

sub rename_mailbox {
    my ( $self, $mbox_name, $new_name ) = @_;
    my ( $sh, $id, $resp, @list );

    $sh = $self->{sock};
    $id = $self->_nextid();

    print $sh "$id RENAME $mbox_name $new_name\n";
    $resp = $sh->getline();

    if ( $resp =~ /^$id\s+OK/i ) {
        return 1;
    }

    return;
}





#############################################################################
#
#
#
#############################################################################

sub copy {
    my ( $self, $msgn, $mbox_name ) = @_;
    my ( $sh, $id, $resp, @list );

    $sh = $self->{sock};
    $id = $self->_nextid();

    print $sh "$id COPY $msgn $mbox_name\n";
    $resp = $sh->getline();

    if ( $resp =~ /^$id\s+OK/i ) {
        return 1;
    }

    return;
}





1;
__END__





=head1 NAME

Net::IMAP::Simple - Perl extension for simple IMAP account handling, mostly 
compatible with Net::POP3.

=head1 SYNOPSIS

    use Net::IMAP::Simple;

    # open a connection to the IMAP server
    $server = new Net::IMAP::Simple( $self->param( 'someserver' ) );

    # login
    $server->login( 'someuser', 'somepassword' );
    
    # select the desired folder
    $number_of_messages = select( 'somefolder' );

    # go through all the messages in the selected folder
    foreach $msg ( 1..$number_of_messages ) {

        # get the message
        $lines = $server->get( $msg );

        # print it
        print @$lines;
    }

    # the list of all folders
    @folders = $server->mailboxes();

    # create a folder
    $server->create_mailbox( 'newfolder' );

    # rename a folder
    $server->rename_mailbox( 'newfolder', 'renamedfolder' );

    # delete a folder
    $server->delete_mailbox( 'renamedfolder' );

    # copy a message to another folder
    $server->copy( $self, $msg, 'renamedfolder' );

    # close the connection
    $server->quit();

=head1 DESCRIPTION

This module is a simple way to access IMAP accounts. The API is mostly
equivalent to the Net::POP3 one, with some aditional methods for mailbox
handling.

=head1 BUGS

I don't know how the module reacts to nested mailboxes.

This module was only tested under Netscape IMAP4rev1 Service 3.6, so
expect some problems with servers from other vendors (then again, if
all of them are implementing the IMAP protocol, it should work - but
we all know how it goes).

=head1 AUTHOR

Joao Fonseca, joao_g_fonseca@yahoo.com

=head1 SEE ALSO

Net::IMAP(1), Net::POP3(1).

=head1 COPYRIGHT

Copyright (c) 1999 Joao Fonseca. All rights reserved.
This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut

