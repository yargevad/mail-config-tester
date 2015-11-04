#!/usr/bin/env perl
# vim:syntax=perl:
use strict;
use Net::DNS;

use lib './lib';
use Msys::Smoke::DNS qw/mx_get is_ip_rdns_valid/;
use Msys::Smoke::Config 'load_test_config';
use Msys::Smoke::TimestampOutput;

my $C = load_test_config();

my $D = Net::DNS::Resolver->new();

my %seen_mx = ();

for my $BIND_NAME ($C->binding_names()) {
  my $DOMAINS = $C->binding_domains($BIND_NAME);
  for my $BIND_DOMAIN (@$DOMAINS) {
    printf STDERR "NOTICE: %s %s\n", $BIND_NAME, $BIND_DOMAIN;
    my @mx = mx_get($BIND_DOMAIN);

    # we start out with the domain name that's used in the MAIL FROM
    # get MX record for domain
    next if not scalar(@mx);

    for my $mx_rr (@mx) {
      # get A records for MX host
      my $ex = $mx_rr->exchange();
      if ($seen_mx{ $ex }) {
        printf STDERR "NOTICE: already tested [%s], skipping\n", $ex;
        next;
      }

      $seen_mx{ $ex }++;
      printf STDERR "NOTICE: found %s [%s] for [%s]\n", $mx_rr->type(), $ex, $BIND_DOMAIN;
      my $mx_a = $D->query($ex, 'A');
      if (not $mx_a) {
        printf STDERR "ERROR: Querying [%s] failed: %s\n", $ex, $D->errorstring();
        next;
      }
      for my $a_rr ($mx_a->answer()) {
        my $ip = $a_rr->address();
        printf STDERR "NOTICE: found %s [%s] for [%s]\n", $a_rr->type(), $ip, $ex;

        # this function call prints a bunch of info
        # TODO? make this less noisy
        my ($valid, $err) = is_ip_rdns_valid(ip => $ip);

      }
    }

  }

  # check rDNS for source IPs configured for each binding
  for my $ips ($C->ip_addresses($BIND_NAME)) {
    for my $ip (@$ips) {
      printf STDERR "NOTICE: %s %s\n", $BIND_NAME, $ip;
      my ($valid, $err) = is_ip_rdns_valid(ip => $ip);
    }
  }
}

