#!/usr/bin/env perl
# vim:syntax=perl:
use strict;
use Net::DNS;

use lib './lib';
use Msys::Smoke::DNS 'dns_query';
use Msys::Smoke::Config 'load_test_config';
use Msys::Smoke::TimestampOutput;

my $C = load_test_config();

my $D = Net::DNS::Resolver->new();

for my $BIND_NAME ($C->binding_names()) {
  my $DOMAINS = $C->binding_domains($BIND_NAME);
  for my $BIND_DOMAIN (@$DOMAINS) {

    my ($txt, $err) = dns_query(host => $BIND_DOMAIN, type => 'txt');
    if (not $txt) {
      print STDERR $err;
      next if $err =~ /\bservfail\b/i;
      my ($spf, $err) = dns_query(host => $BIND_DOMAIN, type => 'spf');
      if (not $spf) {
        print STDERR $err;
      } else {
        for my $ans (@$spf) {
          printf STDERR "FAIL: %s (spf): %s\n", $BIND_DOMAIN, $ans->rdatastr();
        }
      }
    } else {
      for my $ans (@$txt) {
        printf STDERR "PASS: %s (txt) %s\n", $BIND_DOMAIN, $ans->rdatastr();
      }
    }

  }
}

