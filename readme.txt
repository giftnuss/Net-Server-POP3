NAME
    Net::Server::POP3 - The Server Side of the POP3 Protocol

SYNOPSIS
      use Net::Server::POP3;
      startserver(
        severopts    => %options,
        authenticate => \&auth,
        list         => \&list,
        retrieve     => \&retrieve,
        delete       => \&delete,
      );

DESCRIPTION
    This is alpha code. That means it needs work and doesn't yet implement
    everything it should. Don't use it unless you don't mind fixing up the
    parts that you find need fixing up.

    It is strongly recommended to run with Taint checking enabled.

    Stub documentation for this module was created by ExtUtils::ModuleMaker.
    It looks like the author of the extension was negligent enough to leave
    the stub mostly unedited.

    Blah blah blah.

USAGE
    This module is designed to be the server/daemon itself and so to handle
    all of the communication to/from the client(s). The actual details of
    obtaining, storing, and keeping track of messages are left to other
    modules or to the user's own code.

    The main routine is startserver(), which starts the server. The
    following named arguments may be passed to startserver(). All callbacks
    should be passed as coderefs.

    port
        The port to listen on. 110 is the default.

    servertype
        A type of server implemented by Net::Server (q.v.) The default is
        'Fork', which is suitable for installations with a small number of
        users.

    serveropts
        A hashref containing extra named arguments to pass to Net::Server.
        Particularly recommended for security reasons are user, group, and
        chroot. See the docs for Net::Server for more information.

    connect
        An optional callback that, if supplied, will be called when a client
        connects. This is the recommended place to allocate resources such
        as a database connection handle.

    disconnect
        This optional callback, if supplied, is called when the client
        disconnects. If there is any cleanup to do, this is the place to do
        it. Note that message deletion is not handled here, but in the
        delete callback.

    authenticate
        The authenticate callback is passed a username, password, and IP
        address. If the username and password are valid and the user is
        allowed to connect from that address and authenticate by the
        USER/PASS method, then the callback should try to get a changelock
        on the mailbox and return true if successful; it must return false
        if any of that fails.

    apop
        Optional callback for handling APOP auth. If the user attempts APOP
        auth and this callback exists, it will be passed the username, the
        digest sent by the user, and the server greeting. If the user's
        digest is indeed the MD5 digest of the concatenation of the server
        greeting and the shared secret for, that user, then the callback
        should attempt to lock the mailbox and return true if successful;
        otherwise, return false.

    list
        The list callback, given a valid, authenticated username, must
        return a list of message-ids of available messages.

    retrieve
        The retrieve callback must accept a valid, authenticated username
        and a message-id (from the list returned by the list callback) and
        must return the message as a string.

    delete
        This callback gets called with a valid, authenticated username and a
        message-id that the user/client has asked to delete. (This only
        happens in cases where the POP3 protocol says the message should be
        deleted. If the connection terminates abnormally before entering the
        UPDATE state, the callback is not called.) It can do whatever it
        wants, such as mark the message as deleted, actually delete it, mark
        it as no longer to be given to this specific user, or whatever.

BUGS
    At this time, servertype is ignored, and Net::Server::Fork is always
    used.

SUPPORT
AUTHOR
            Jonadab the Unsightly One (Nathan Eady)
            jonadab@bright.net
            http://www.bright.net/~jonadab/

COPYRIGHT
    This program is free software licensed under the terms of...

            The BSD License

    The full text of the license can be found in the LICENSE file included
    with this module.

SEE ALSO
    perl(1). Net::Server(1).

  sample_function

     Usage     : How to use this function/method
     Purpose   : What it does
     Returns   : What it returns
     Argument  : What it wants to know
     Throws    : Exceptions and other anomolies
     Comments  : This is a sample subroutine header.
               : It is polite to include more pod and fewer comments.

    See Also :

