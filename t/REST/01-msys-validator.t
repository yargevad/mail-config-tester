#!/usr/bin/env perl
# vim:syntax=perl:
use strict;
$|++;

use JSON;
use LWP::UserAgent;
use Data::Dumper;
use File::Path 'make_path';

use lib './lib';
use Msys::Smoke::DNS qw/dns_query mx_get_ips/;
use Msys::Smoke::Config 'load_test_config';
use Msys::Smoke::Validator;
use Msys::API::v1::Transmission qw/
  replace_recipient
  default_transmission_json
/;
use Msys::Smoke::TimestampOutput;

# get the config object for the customer that's configured for testing
my $C = load_test_config();
my $T = Msys::API::v1::Transmission->new(config => $C);

for my $BIND_NAME ($C->binding_names()) {
  my $DOMAINS = $C->binding_domains($BIND_NAME);
  my %IPS = map(($_ => 1), @{ $C->ip_addresses($BIND_NAME) });
  for my $BIND_DOMAIN (@$DOMAINS) {
    my %MX_IPS = map(($_->address() => 1), mx_get_ips($BIND_DOMAIN));
    # keep sending until we see all of the expected IPs
    my %seen_ips = (map(($_ => 0), @{ $C->ip_addresses($BIND_NAME) }));
    my $MAIL_FROM = sprintf('smoke.tester@%s', $BIND_DOMAIN);
    my $SUBJECT = sprintf('%s %s test REST-01 %s', $BIND_DOMAIN, $BIND_NAME, time);

    my $headers = $C->custom_headers($BIND_NAME);
    my $data = default_transmission_json(
      bind_domain => $BIND_DOMAIN,
      mail_from   => $MAIL_FROM,
      subject     => $SUBJECT,
      (scalar(keys(%$headers))
        ? (headers => $headers)
        : ()),
    );

    while (scalar(grep($seen_ips{$_} == 0, keys(%seen_ips))) > 0) {
      my $V = Msys::Smoke::Validator->new(config => $C);

      my ($addr, $err) = $V->generate_address();
      if (not $addr) {
        printf STDERR "ERROR: %s\n", $err;
        exit(1);
      }
      my $RCPT_TO = $addr->{address};
      printf STDERR "NOTICE: generated address [%s]\n", $RCPT_TO;

      replace_recipient($data,
        email => $RCPT_TO,
        name => sprintf('Smoke Tester (%s)', $C->{subdomain}),
        metadata => { binding => $BIND_NAME },
      );

      my ($res, $err) = $T->post_entry($data);

      # assert that transmission was accepted
      if (not $res) {
        print STDERR $err;
        die "failed to connect!";
      }
      if (not $res->{results} or $res->{results}{total_rejected_recipients}) {
        print $T->last_error();
        die "transmission rejected!";
      }
      my $tid = $res->{results}{id};
      printf STDERR "tid=[%s] from=[%s] to=[%s] binding=[%s] subject=[%s] \n",
        $tid, $MAIL_FROM, $RCPT_TO, $BIND_NAME, $SUBJECT;

      my $vr = $V->wait_for_validator_results(
        email => $RCPT_TO,
      );
      # TODO: automatically add domain to validator's domain whitelist
      if (not $vr->{message}) {
        printf "WARNING: no message data captured for [%s]\n", $BIND_DOMAIN;
      } else {
        # save message, print filenames
        my $msg_dir = sprintf('msg/%s/%s', $C->test_customer(), $BIND_DOMAIN);
        make_path($msg_dir);
        my $msg_fn = sprintf('%d.%s.eml', $tid, 'REST-01');
        my $fn = sprintf('%s/%s', $msg_dir, $msg_fn);
        open my $fh, '>', $fn;
        if (not $fh) {
          printf "WARNING: couldn't save message: %s\n", $!;
        } else {
          print $fh $vr->{message};
          close $fh;
          printf "NOTICE: wrote message to [%s]\n", $fn;
        }
      }

      if ($seen_ips{ $vr->{ip} }) {
        printf "NOTICE: already saw %s; left (%s)\n",
          $vr->{ip}, join(', ', grep($seen_ips{$_} == 0, keys(%seen_ips)));
        next;
      }
      $seen_ips{ $vr->{ip} }++;

      printf "Validator results for binding %s domain %s:\n", $BIND_NAME, $BIND_DOMAIN;
      # print out domain part of Message-ID header(s) to show generating node
      if ($vr->{message}) {
        my @msgid = ($vr->{message} =~ /^(message\-id:.*?(?=[\r\n]+\S))/ismg);
        # collapse each header down to one line
        s/[\r\n]+\s+//g for @msgid;
        for my $msgid (@msgid) {
          my ($domain) = ($msgid =~ /\@([^@]+?)>?\s*$/);
          printf "  MsgID Domain:\t%s\n", $domain;
        }
      }
      printf "  Domain / IP:\t%s / %s\n", $vr->{domain}, $vr->{ip};
      # check IP against configured ones
      if (not $IPS{ $vr->{ip} }) {
        printf "    ERROR: %s saw IP %s; config (%s)\n",
          $BIND_DOMAIN, $vr->{ip}, join(', ', keys(%IPS));
      }

      # check IP against MXs
      if (not $MX_IPS{ $vr->{ip} }) {
        printf "    ERROR: %s saw IP %s; MX (%s)\n",
          $BIND_DOMAIN, $vr->{ip}, join(', ', keys(%MX_IPS));
      }

      printf "  PTR / EHLO:\t%s\n", $vr->{ptr_ehlo_match};

      printf "  SPF Result:\t%s\n", $vr->{spf_status};
      # on SPF fail, display results for both TXT and SPF records
      # that's the common error, to set the record type to SPF
      if ($vr->{spf_status} =~ /^FAIL\b/) {
        my ($txt, $err) = dns_query(host => $BIND_DOMAIN, type => 'txt');
        if (not $txt) {
          print $err;
          my ($spf, $err) = dns_query(host => $BIND_DOMAIN, type => 'spf');
          if (not $spf) {
            print $err;
          } else {
            for my $ans (@$spf) {
              printf "    ERROR: %s (spf): %s\n", $BIND_DOMAIN, $ans->rdatastr();
            }
          }
        } else {
          for my $ans (@$txt) {
            printf "    NOTICE: %s (txt) %s\n", $BIND_DOMAIN, $ans->rdatastr();
          }
        }
      }

      # use message contents from validator to check selector
      printf "  DKIM Result:\t%s\n", $vr->{dkim};
      if ($vr->{message}) {
        # pull all multi-line dkim headers
        my @dkim = ($vr->{message} =~ /^(dkim\-signature:.*?(?=[\r\n]+\S))/ismg);
        # collapse each header down to one line
        s/[\r\n]+\s+//g for @dkim;
        # print out the domain and selector for each signature
        for my $dkim (@dkim) {
          my ($domain) = ($dkim =~ /\bd=(.*?);/);
          my ($selector) = ($dkim =~ /\bs=(.*?);/);
          printf "    %s: %s\n", $domain, $selector;
        }
      }
      printf "  DMARC Result:\t%s\n", $vr->{dmarc};

      printf "  Link Result:\n";
      # search message for links, check link domain against configured
      if ($vr->{message}) {
        if (not $C->{link_domain}) {
          printf "    WARNING: no link_domain configured for [%s]\n", $C->test_customer();
        }
        my $msg = $vr->{message};
        my %domains = ();
        while ($msg =~ m{\b(https?)://([^/]*?)(/.*?)?(?=["\s]|$)}g) {
          my $hr = { scheme => $1, domain => $2, path => $3 };
          $domains{ $2 } ||= [];
          push @{ $domains{ $2 } }, $hr;
        }

        if ($C->{link_domain}) {
          printf "    %d matches for %s\n",
            scalar(@{ $domains{ $C->{link_domain} } || [] }), $C->{link_domain};
          # TODO: if there are links, fetch them, check for link redirects or open images
        }
        for my $domain (sort
          { scalar(@{ $domains{ $b } || [] }) <=> scalar(@{ $domains{ $a } || [] }) }
          keys %domains
        ) {
          next if $domain eq $C->{link_domain};
          printf "    %d links with %s\n", scalar(@{ $domains{ $domain } || [] }), $domain;
        }
      }
    }
  }
}

