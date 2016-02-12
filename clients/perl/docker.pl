#!/usr/bin/perl
use strict;
use warnings;

print "1\n";

sub register {
}

sub update {
}

sub make_request {
  open ( my $fh, '-|', 'ls', '-l' );
  print (<$fh>);
}

make_request()
