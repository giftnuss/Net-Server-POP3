#!/usr/bin/perl -w -T

our $debug = 1; $|++; use Data::Dumper; # Yes, it's that alpha.
use strict; use warnings;

BEGIN { push @INC, "/home/mailproxy/lib"; } # You can comment this out if you install Net::Server::POP3 in a normal place.

use Net::Server::POP3;
use DateTime; use DateTime::Format::Mail;
use Mail::POP3Client;


