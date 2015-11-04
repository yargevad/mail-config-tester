#!/usr/bin/env perl
# vim:syntax=perl:
use strict;
use local::lib;

=cut
This test sanity checks that various types of inbound messages are accepted
into the system, i.e. not rejected after RCPT TO.
Testing that actually generates and delivers messages is also necessary, to
catch config issues like the binding not existing, for example.
=cut

use lib './lib';
use Msys::Smoke::DNS 'mx_get';
use Msys::Smoke::Config 'load_test_config';
use Msys::Smoke::TimestampOutput;

use Net::SMTPS;

my $C = load_test_config();

my $SSL  = 'undef'; # starttls / ssl / undef

my %domains = ();
for my $BIND_NAME ($C->binding_names()) {
  my $DOMAINS = $C->binding_domains($BIND_NAME);
  for my $BIND_DOMAIN (@$DOMAINS) {
    next if $domains{ $BIND_DOMAIN };
    $domains{ $BIND_DOMAIN }++;

    for my $lp (qw/abuse postmaster bounces-abc inbound/) {
      # make this easier to search for
      my $FROM = sprintf('smoke.tester+%d@%s', time, $BIND_DOMAIN);
      my $TO   = sprintf('%s@%s', $lp, $BIND_DOMAIN);

      # auto-detect MX for this domain
      my @mx = mx_get($BIND_DOMAIN);
      if (not scalar(@mx)) {
        printf STDERR "ERROR: no MX for domain [%s]\n", $BIND_DOMAIN;
        next;
      }
      my $MX = $mx[0]->exchange();

      my $smtp = Net::SMTPS->new($MX,
        #Debug => 1,
        Port  => 25,
        doSSL => $SSL,
      );
      # detect connection failure
      if (not $smtp) {
        printf STDERR "ERROR: connection to [%s] failed\n", $MX;
        next;
      }

      my $smtp_rc = $smtp->mail($FROM);
      if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
        printf STDERR "ERROR: MAIL FROM [%s] failed!\n", $FROM;
        next;
      }

      $smtp_rc = $smtp->to($TO);
      if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
        if ($lp eq 'inbound') {
          # we expect "relaying denied" here
          printf STDERR "NOTICE: RCPT TO [%s] failed (%s)\n", $TO, $FROM;
        } else {
          printf STDERR "ERROR: RCPT TO [%s] failed! (%s)\n", $TO, $FROM;
        }
        next;
      }

      printf STDERR "NOTICE: RCPT TO accepted: from (%s) to (%s@%s)\n", $FROM, $lp, $BIND_DOMAIN;

    }
  }
}

