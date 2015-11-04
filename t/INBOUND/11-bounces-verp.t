#!/usr/bin/env perl
# vim:syntax=perl:
use strict;
use local::lib;

use lib './lib';
use Msys::Smoke::DNS 'mx_get';
use Msys::Smoke::Config 'load_test_config';
use Msys::Smoke::WebHookInbox;
use Msys::Smoke::TimestampOutput;

use Net::SMTPS;
use MIME::Lite;
use MIME::Base64 'encode_base64';

my $C = load_test_config();

my $SSL  = 'undef'; # starttls / ssl / undef

## create a webhook bucket, and then a webhook
#my $IN = Msys::Smoke::WebHookInbox->new();
#$IN->create();
#my $rv = $IN->setup({
#  config => $C,
#  events => [qw/
#    injection delivery bounce delay
#    out_of_band policy_rejection
#  /],
#});
#if (not defined($rv)) {
#  printf STDERR "ERROR: failed to set up web hook!\n";
#  exit(1);
#}

for my $BIND_NAME ($C->binding_names()) {
  my $DOMAINS = $C->binding_domains($BIND_NAME);
  for my $BIND_DOMAIN (@$DOMAINS) {
    my $FROM = sprintf('smoke.tester+%d@%s', time, $BIND_DOMAIN);
    my $TO   = sprintf('bounces-msys-smoke-test-%s-%s@%s', $ENV{USER}, time, $BIND_DOMAIN);

    my $msg = MIME::Lite->new(
      From    => $FROM,
      To      => $TO,
      Subject => sprintf('%s %s test INBOUND-02 %s', $C->{subdomain}, $BIND_NAME, time),
      Type    => 'multipart/alternative',
    );

    $msg->attach(
      Type => 'TEXT',
      Data => "Hi there,\nSmoke test email from Message Systems!\nTest link: http://www.messagesystems.com\nSmoke Tester",
    );

    $msg->attach(
      Type => 'text/html',
      Data => qq'<p>Hi there<br/>\nSmoke test email from Message Systems!<br/>\nTest Link: <a href="http://www.messagesystems.com">messagesystems.com</a><br/>\n</p><p>Smoke Tester</p>',
    );

    my $msg_str = $msg->as_string();
    $msg_str =~ s/\r?\n/\r\n/g;

    # auto-detect MX for this domain
    my @mx = mx_get($BIND_DOMAIN);
    if (not scalar(@mx)) {
      printf "ERROR: no MX for domain [%s]\n", $BIND_DOMAIN;
      next;
    }
    my $MX = $mx[0]->exchange();

    my $smtp = Net::SMTPS->new($MX,
      #Debug => 1,
      Port  => 25,
      doSSL => $SSL,
    );

    #my $smtp_rc = $smtp->mail($FROM);
    my $smtp_rc = $smtp->mail('<>');
    if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
      printf "ERROR: MAIL FROM [%s] failed!\n", $FROM;
      exit(1);
    }

    $smtp_rc = $smtp->to($TO);
    if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
      printf "ERROR: RCPT TO [%s] failed! (%s)\n", $TO, $FROM;
      exit(1);
    }

    $smtp_rc = $smtp->data($msg_str);
    if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
      print "ERROR: DATA failed!\n";
      exit(1);
    }

    printf "NOTICE: from (%s) to (%s)\n", $FROM, $TO;
    #$IN->{verbose} = 1;
    #my $e = $IN->events_with_rcpt_to({
    #  rcpt_to => $TO,
    #  expected => {
    #    out_of_band => 1,
    #    policy_rejection => 1,
    #  },
    #});
  }
}

# confirm OOB classification:
# - "550 [internal] [oob] The response text could not be identified."

