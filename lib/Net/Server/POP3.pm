#!/usr/bin/perl -w -T
# -*- cperl -*-
package Net::Server::POP3;
use Data::Dumper; $|++; # For debugging.  This can eventually be removed, but right now I need it.
use strict;
my %parameters; my @message; my @deleted;

# These are the RFCs that I know about and intend to implement:
# http://www.faqs.org/rfcs/rfc1939.html
# http://www.faqs.org/rfcs/rfc2449.html

BEGIN {
	use Exporter ();
	use vars qw ($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
	$VERSION     = 0.0001;
	@ISA         = qw (Exporter);
	@EXPORT      = qw ();
	@EXPORT_OK   = qw (startserver op user);
	%EXPORT_TAGS = ();
}

sub nop {return}; # Used as default for optional callbacks.

my %op; my %user;

sub startserver {
  my $self = shift;
  %op = (%parameters, @_);
  my %serveropts; %serveropts = %{$op{serveropts}} if exists $op{serveropts};
  $op{port}         ||= 110;
  $op{servertype}   ||= 'Fork';
  $op{authenticate} ||= \&nop; # Authorizes nobody; you must provide the callback to change this.
  $op{delete}       ||= \&nop; # It is strongly recommended to provide a delete callback.
  $op{connect}      ||= \&nop;
  $op{disconnect}   ||= \&nop;
  $op{welcome}      ||= "Welcome to my Test POP3 Server.  Some stuff does not work yet.";

  exists $op{list} or die "The list callback is required.";
  exists $op{retrieve} or die "The retrieve callback is required.";

  # use Net::Server::Fork; # We want to fix this to use $op{servertype}
  eval "use Net::Server::$op{servertype}";
  push @ISA, "Net::Server::$op{servertype}";
  Net::Server::POP3->run(port => $op{port}, %serveropts);
}

sub messagesize {
  my ($msgnum) = @_;
  if ($op{size}) {
    return $op{size}->($message[$msgnum-1]);
  } else {
    return length($op{retrieve}->($user{name}, $message[$msgnum-1]));
    # This kills efficiency, so if you care about that you should
    # supply the size callback.
  }
}

sub boxsize {
  my $totalsize = 0; my $msgnum;
  for (@_) { $totalsize += messagesize(++$msgnum) }
  return $totalsize;
}

sub scanlisting {
  # returns a scan listing for each message number in @_

  warn "scanlisting @_\n" if $main::debug;
  # In order to simplify parsing, all POP3 servers are required to use
  # a certain format for scan listings.  A scan listing consists of
  # the message-number of the message, followed by a single space and
  # the exact size of the message in octets.
  my $msgnum = shift;
  my $size = messagesize($msgnum);
  die "Message $msgnum (user $user{name}) has no size!$/" unless ($size>0);
  return "$msgnum $size";
}

sub process_request { # The name of this sub is magic for Net::Server.
    my $self = shift;

    $op{connect}->();
    eval {
      print "+OK $op{welcome}\n";

      local $SIG{ALRM} = sub { die "Timed Out!\n" };
      my $timeout = 600; # give the user this many seconds to type a
                         # line My reading of RFC1939 is that this
                         # shouldn't be less than ten minutes (at
                         # least, between commands).

      my $previous_alarm = alarm($timeout);
      my $state = 0; # 0 = not authenticated.  1 = authenticated.
      while (<STDIN>) {
        # s/\r?\n$//;
        chomp;
        if ($state) {
          # We _are_ authenticated.  Let user do stuff.
          if (/^STAT/i) {
            print "+OK ".(scalar @message)." ".boxsize(@message)."\n";
          } elsif (/^VERSION/i) {
            print "+OK Net::Server::POP3 $VERSION\n";
          } elsif (/^LIST\s*(\d*)/i) {
            my $msgnum = $1;
            if ($msgnum) {
              # If an argument was given and the POP3 server issues a
              # response with a line containing information for that
              # message.  This line is called a "scan listing" for
              # that message.
              if ($msgnum <= @message) {
                print "+OK " . scanlisting($msgnum)."\n";
              } else {
                # Most clients won't even try this.
                print "-ERR Cannot find message $msgnum (only ".@message." in drop)\n";
              }
            } else {
              # If no argument was given and the POP3 server issues a
              # positive response, then the response given is
              # multi-line.  After the initial +OK, for each message
              # in the maildrop, the POP3 server responds with a line
              # containing information for that message.  This line is
              # also called a "scan listing" for that message.  If
              # there are no messages in the maildrop, then the POP3
              # server responds with no scan listings--it issues a
              # positive response followed by a line containing a
              # termination octet and a CRLF pair.
              print "+OK scan listing follows\n";
              for (@message) {
                ++$msgnum;
                if (not $deleted[$msgnum-1]) {
                  # RFC1939 sez: Note that messages marked as deleted are not listed.
                  print scanlisting($msgnum)."\n";
                }
              }
              print ".\n";
            }
          } elsif (/^UIDL\s*(\d*)/i) {
            my $msgnum = $1;
            if ($msgnum) {
              # If an argument was given and the POP3 server issues a
              # positive response with a line containing information
              # for that message.  This line is called a "unique-id
              # listing" for that message.
              if ($msgnum <= @message) {
                print "+OK $msgnum " . $message[$msgnum-1] . "\n";
              } else {
                # Most clients won't even try this.
                print "-ERR Cannot find message $msgnum (only ".@message." in drop)\n";
              }
            } else {
              # If no argument was given and the POP3 server issues a
              # positive response, then the response given is
              # multi-line.  After the initial +OK, for each message
              # in the maildrop, the POP3 server responds with a line
              # containing information for that message.  This line is
              # called a "unique-id listing" for that message.
              print "+OK message-id listing follows\n";
              for (@message) {
                ++$msgnum;
                if (not $deleted[$msgnum-1]) {
                  print "$msgnum $_\n";
                }
              }
              print ".\n";
            }
          } elsif (/^TOP\s*(\d+)\s*(\d+)/i) {
            # RFC lists TOP as optional, but Mozilla Messenger seems to require it.
            my ($msgnum, $toplines) = ($1, $2);
            # If the POP3 server issues a positive response, then the
            # response given is multi-line.  After the initial +OK,
            # the POP3 server sends the headers of the message, the
            # blank line separating the headers from the body, and
            # then the number of lines of the indicated message's
            # body, being careful to byte-stuff the termination
            # character (as with all multi-line responses).
            # Note that if the number of lines requested by the POP3
            # client is greater than than the number of lines in the
            # body, then the POP3 server sends the entire message.
            my ($head, $body) = split /\n\n/, $op{retrieve}->($user{name}, $message[$msgnum-1]), 2;
            my ($hl, $bl) = (length $head, length $body);
            print "+OK top of message follows ($hl octets in head and $bl octets in body up to $toplines lines)\n";
            for (split /\n/m, $head) {
              chomp;
              s/^/./ if /^[.]/;
              print "$_\n";
            }
            print "\n";
            my $lnum;
            for (split /\n/m, $body) {
              chomp;
              s/^/./ if /^[.]/;
              print "$_\n" if ++$lnum <= $toplines;
            }
            print ".\n";
          } elsif (/^RETR\s*(\d*)/i) {
            my ($msgnum) = $1;
            if ($msgnum <= @message) {
              print "+OK sending $msgnum " . $message[$msgnum-1] . "\n";
              warn "Sending message $msgnum:\n" if $main::debug;
              warn "\@message is as follows: " . Dumper(\@message) . "\n" if $main::debug;
              my $msgid = $message[$msgnum-1];
              warn "message id is $msgid\n" if $main::debug;
              die "No retrieve callback\n" unless ref $op{retrieve};
              my $msg = $op{retrieve}->($user{name}, $msgid);
              warn "Retrieved message\n" if $main::debug;
              if (not $msg =~ /\n\n/m) {  warn "Message $msgnum ($msgid) seems very wrong:\n$msg\n"; die "Suffering and Pain!\n"; }
              warn "Message is as follows: " . Dumper($msg) . "\n" if $main::debug;
              for (split /\n/, $msg) {
                chomp;
                s/^/./ if /^[.]/;
                print "$_\n";
                warn "$_\n" if $main::debug;
              }
              print ".\n";
            } else {
              # Most clients won't even try this.
              print "-ERR Cannot find message $msgnum (only ".@message." in drop)\n";
            }
          } elsif (/^DELE\s*(\d*)/i) {
            my ($msgnum) = $1;
            if ($msgnum <= @message) {
              $deleted[$msgnum-1]++;
              # Any future reference to the message-number associated
              # with the message in a POP3 command generates an error,
              # according to the RFC, but in practice clients should
              # simply not do that, so it can be something we
              # implement later, after most stuff works.
              print "+OK marking message number $msgnum for later deletion.\n";
              # The POP3 server does not actually delete the message
              # until the POP3 session enters the UPDATE state.
            } else {
              # Most clients won't even try this.
              print "-ERR Cannot find message $msgnum (only ".@message." in drop)\n";
            }
          } elsif (/^QUIT/i) {
            my $msgnum = 0;
            for (@message) {
              if ($deleted[++$msgnum]) {
                if ($op{delete}) {
                  # Yes, this is optional so that highly minimalistic
                  # implementations can skip it, but any serious mail
                  # server will obviously need to supply the delete
                  # callback.
                  $op{delete}->($user{name}, $message[$msgnum-1]);
                }
              }
            }
            print "+OK Bye, closing connection...\n";
            $op{disconnect}->();
            return 0;
          } elsif (/^NOOP/) {
            print "+OK nothing to do.\n";
          } elsif (/^RSET/) {
            @deleted = ();
            print "+OK now no messages are marked for deletion at end of session.\n";
          } elsif (/^CAPA/) {
            print capabilities(1); # The 1 indicates we are in the transaction state.
          } else {
            print STDERR "Client said \"$_\" (which I do not understand in the transaction state)\n";
            print "-ERR That must be something I have not implemented yet.\n";
          }
        } else {
          # We're not authenticated yet.  Try to authenticate.
          if (/^QUIT/i) {
            print "+OK Bye, closing connection...\n";
            $op{disconnect}->();
            return 0;
          } elsif (/^VERSION/i) {
            print "+OK Net::Server::POP3 $VERSION\n";
          } elsif (/^USER\s*(\S*)/i) {
            $user{name} = $1;  delete $user{pass};
            print "+OK $user{name} knows where his towel is; use PASS to authenticate\n";
          } elsif (/^PASS\s*(.*?)\s*$/i) {
            $user{pass} = $1;
            if ($user{name}) {
              if ($op{authenticate}->(@user{'name','pass'})) { # TODO:  also pass IP addy
                $state = 1;
                @message = $op{list}->($user{name});
                warn "Have maildrop: " . Dumper(\@message) . "\n" if $main::debug;
                print "+OK $user{name}'s maildrop has ".@message." messages (".boxsize(@message)." octets)\n";
              } else {
                delete $user{name};
                print "-ERR Unable to lock maildrop at this time with that auth info\n";
              }
            } else {
              print "-ERR You can only use PASS right after USER\n";
            }
          } elsif (/^APOP/) {
            print "-ERR APOP/MD5 authentication not yet implemented, try USER/PASS\n";
          } elsif (/^CAPA/) {
            print capabilities(0); # The zero means we're not authenticated yet.
          } else {
            print STDERR "Client said \"$_\" (which I do not understand in the unauthenticated state)\n";
            print "-ERR That must be something I have not implemented yet, or you need to authenticate.\n";
          }
        }
        alarm($timeout);
      }
      alarm($previous_alarm);

    };

      if ($@=~/timed out/i) {
      print STDOUT "-ERR Timed Out.\n";
      return;
    }
}

########################################### main pod documentation begin ##

=head1 NAME

Net::Server::POP3 - The Server Side of the POP3 Protocol

=head1 SYNOPSIS

  use Net::Server::POP3;
  my $server = Net::Server::POP3->new(
    severopts    => \%options,
    authenticate => \&auth,
    list         => \&list,
    retrieve     => \&retrieve,
    delete       => \&delete,
    size         => \&size,
    welcome      => "Welcome to my mail server.",
  );
  $server->startserver();

=head1 DESCRIPTION

This is alpha code.  That means it needs work and doesn't yet implement
everything it should.  Don't use it unless you don't mind fixing up the
parts that you find need fixing up.  Lots of parts still need fixing.
You have been warned.

The code as it stands now works, for some definition of "works".  With
the included simpletest.pl script I have successfully served test
messages that I have retrieved with Mozilla Mail/News.  However, much
work remains to be done.

It is strongly recommended to run with Taint checking enabled.

Stub documentation for this module was created by ExtUtils::ModuleMaker.
It looks like the author of the extension was negligent enough
to leave the stub at least partly unedited.

=head1 USAGE

This module is designed to be the server/daemon itself and so to
handle all of the communication to/from the client(s).  The actual
details of obtaining, storing, and keeping track of messages are left
to other modules or to the user's own code.  (See the sample script
simpletest.pl for an example.)

The main method is startserver(), which starts the server.  The
following named arguments may be passed either to new() or to
startserver().  All callbacks should be passed as coderefs.
If you pass an argument to new() and then pass an argument of
the same name to startserver(), the one passed to startserver()
overrides the one passed to new().  stopserver() has not been
implemented yet and so neither has restartserver().

=over

=item port

The port number to listen on.  110 is the default.  You only need to
supply a port number if you want to listen on a different port.

=item servertype

A type of server implemented by Net::Server (q.v.)  The default is
'Fork', which is suitable for installations with a small number of
users.  You only need to supply a servertype if you want to use a
different type other than 'Fork'.

=item serveropts

A hashref containing extra named arguments to pass to Net::Server.
Particularly recommended for security reasons are user, group, and
chroot.  See the docs for Net::Server for more information.

The serveropts hashref is optional.  You only need to supply it if you
have optional arguments to pass through to Net::Server.

=item connect

This callback, if supplied, will be called when a client connects.
This is the recommended place to allocate resources such as a database
connection handle or a lock on the maildrop.

The connect callback is optional; you only need to supply it if you
have setup to do when a client connects.

=item disconnect

This callback, if supplied, is called when the client disconnects.  If
there is any cleanup to do, this is the place to do it.  Note that
message deletion is not handled here, but in the delete callback.

The disconnect callback is optional; you only need to supply it if you
have cleanup to do when a client disconnects.

=item authenticate

The authenticate callback is passed a username, password, and IP
address.  If the username and password are valid and the user is
allowed to connect from that address and authenticate by the USER/PASS
method, then the callback should try to get a changelock on the
mailbox and return 1 if successful; it must return something other
than 1 if any of that fails.  (Returning 0 does not specify the
details of what went wrong; other values may in future versions have
particular meanings.)

The authenticate callback is technically optional, but you need to
supply it if you want any users to be able to log in using the USER
and PASS commands.

=item apop

Optional callback for handling APOP auth.  If the user attempts APOP
auth and this callback exists, it will be passed the username, the
digest sent by the user, and the server greeting.  If the user's
digest is indeed the MD5 digest of the concatenation of the server
greeting and the shared secret for that user, then the callback
should attempt to lock the mailbox and return true if successful;
otherwise, return false.

The apop callback is only needed if you want to supply APOP
authentication.

This is not implemented yet, but I plan to implement it.

=item list

The list callback, given a valid, authenticated username, must return
a list of message-ids of available messages.  (Most implementations
will ingore the username, since they will already be locked in to the
correct mailbox after authentication.  That's fine.  The username is
passed as a help for minimalist implementations.)

The list callback is required.

=item retrieve

The retrieve callback must accept a valid, authenticated username and
a message-id (from the list returned by the list callback) and must
return the message as a string.  (Most implementations will ingore the
username, since they will already be locked in to the correct mailbox
after authentication.  That's fine.  The username is passed as a help
for minimalist implementations.)

The retrieve callback is required.

=item delete

The delete callback gets called with a valid, authenticated username
and a message-id that the user/client has asked to delete.  (Most
implementations will ingore the username, since they will already be
locked in to the correct mailbox after authentication.  That's fine.
The username is passed as a help for minimalist implementations.)  The
callback is only called in cases where the POP3 protocol says the
message should actually be deleted.  If the connection terminates
abnormally before entering the UPDATE state, the callback is not
called, so code using this module does not need to concern itself with
marking and unmarking for deletion.  When called, it can do whatever
it wants, such as actually delete the message, archive it permanently,
mark it as no longer to be given to this specific user, or whatever.

This callback is technically optional, but you'll need to supply one
if you want to know when to remove messages from the user's maildrop.

=item welcome

This string is used as the welcome string.  It must not be longer than
507 bytes, for arcane reasons involving RFC1939.  (The length is not
checked automatically by Net::Server::POP3, though it may be in a
future version.)  This is optional; a default welcome is supplied.

=item logindelay

If a number is given, it will be announced in the capabilities list as
the minimum delay (in seconds) between successive logins by the same
user (which applies to any user).  This does NOT enforce the delay; it
only causes it to be announced in the capabilities list.  The
authenticate callback is responsible for enforcement of the delay.
The delay SHOULD be enforced if it is announced (RFC 2449).

If the delay may vary per user, logindelay should be a callback
routine.  If the callback is passed no arguments, it is being asked
for the maximum delay for all users; if it is passed an argument, this
will be a valid, authenticated username and the callback should return
the delay for that particular user.  Either way, the return value
should be a number of seconds.  Again, this does NOT enforce the
delay; it only causes it to be announced in the capabilities list.
(Some clients may not even ask for the capabilities list, if they do
not implement POP3 Extensions (RFC 2449).)

The default is not to announce any particular delay.

=item expiretime

If a number or the string 'NEVER' is given, it will be announced in
the capabilities list as the length of time a message may remain on
the server before it expires and may be automatically deleted by the
server.  (The number is a number of days.)

This does NOT actually delete anything; it just announces the
timeframe to the client.  Clients that do not support POP3 Extensions
will not get this announcement.  'NEVER' means the server will never
expire messages; 0 means that expiration is immanent and the client
should not count on leaving messages on the server.  0 should be
announced for example if the mere act of retrieving a message may
cause it to expire shortly afterward.

If the message expiration time may vary by user, expiretime should be
a callback routine.  If the callback is passed no arguments, it is
being asked for the minimum expiration time for all users, which it
should return (as a whole number of days; 0 is acceptable); if it is
passed an argument, this will be a valid, authenticated username and
the callback should return the expiration time for this particular
user, either as a whole number of days or the string 'NEVER'.

The default is not to announce an expiration time.

=back

=head1 BUGS

Some things are just plain not implemented yet.  The UIDL
implementation uses the message-id as the unique id, rather than
calculating a hash as suggested by RFC 1939.  In practice, this seems
to be what my ISP's mail server does (it calls itself InterMail),
which has worked with every client I've thrown at it, so it should be
mostly okay, but it's not strictly up to spec I think and may be
changed in a later version.  There may be other bugs as well; this is
very alpha stuff.  Significant changes may be made to the code
interface before release quality is reached, so if you use this module
now you may have to change your code when you upgrade.  Caveat user.

=head1 SUPPORT

Use the source, Luke.  You can also contact the author with questions,
but I cannot guarantee that I will be able to answer all of them in a
satisfactory fashion.  The code is supplied on an as-is basis with no
warranty.

=head1 AUTHOR

	Jonadab the Unsightly One (Nathan Eady)
	jonadab@bright.net
	http://www.bright.net/~jonadab/

=head1 COPYRIGHT

This program is free software licensed under the terms of...

	The BSD License

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

  perl(1)
  Net::Server http://search.cpan.org/search?query=Net::Server
  Mail::POP3Client http://search.cpan.org/search?query=Mail::POP3Client

=cut

############################################# main pod documentation end ##


################################################ subroutine header begin ##

=head2 sample_function

 Usage     : How to use this function/method
 Purpose   : What it does
 Returns   : What it returns
 Argument  : What it wants to know
 Throws    : Exceptions and other anomolies
 Comments  : This is a sample subroutine header.
           : It is polite to include more pod and fewer comments.

See Also   : 

=cut

################################################## subroutine header end ##

sub new
{
  ((my $class), %parameters) = @_;

  my $self = bless ({}, ref ($class) || $class);

  return ($self);
}

sub capabilities {
  my ($state) = @_; # 1 for transaction state, 0 for no.
  my $response = "+OK capability list follows.";
  my @capa = (
              'TOP',
              'USER',
              # 'SASL mechanisms', # SASL auth is specified in a separate RFC someplace.
              # 'RESP-CODES', # Response codes as specified in RFC 2449.
              # 'PIPELINING', # I *think* this should Just Work(TM), given the way Perl handles sockets, but I'm NOT sure, so I'm leaving this turned off for now.
              'UIDL',
              "IMPLEMENTATION Net::Server::POP3 version_$VERSION",
             );
  if (exists $op{logindelay}) {
    if (ref $op{logindelay}) { # It's a callback; the actual delay can vary by user...
      my $delay; if ($state) { # Transaction state.  Get the value for *this* user:
        $delay = $op{logindelay}->($user{name});
      } else { # Authentication state.  Get the max value for all users:
        $delay = ($op{logindelay}->() . " USER"); }
      push @capa, "LOGIN-DELAY $delay"
    } else { # A number:  it must be the same number for all users:
      push @capa, "LOGIN-DELAY $op{logindelay}"
    }
  }
  if (exists $op{expiretime}) {
    if (ref $op{expiretime}) { # It's a callback; the actual time can vary by user...
      my $expire; if ($state) { # Get the value for *this* user:
        $expire = $op{expiretime}->($user{name});
      } else { # We're not authenticated:  get the min value for all users:
        $expire = ($op{expiretime}->() . " USER");
      }
      push @capa, "EXPIRE $expire";
    } else { # It's the same number for all users:
      push @capa, "EXPIRE $op{expiretime}";
    }
  }
  return "$response\n".
    (join "\n", @capa).".\n";
}

42; #this line is important and will help the module return a true value
__END__

