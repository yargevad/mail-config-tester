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
#my $IN = Msys::Smoke::WebHookInbox->new(config => $C);
#$IN->create();
#sleep(2); # wait a tick for the inbox to be created
#my $rv = $IN->setup({
#  config => $C,
#  events => [qw/
#    injection delivery bounce delay
#    policy_rejection spam_complaint
#  /],
#  DEBUG => 1,
#});
#if (not defined($rv)) {
#  printf STDERR "ERROR: failed to set up web hook!\n";
#  exit(1);
#}

# TODO: get msg_spoolname from reception event that has the right mail_from and rcpt_to
#       and use that to find other relevant events

for my $BIND_NAME ($C->binding_names()) {
  my $DOMAINS = $C->binding_domains($BIND_NAME);
  for my $BIND_DOMAIN (@$DOMAINS) {

    for my $lp (qw/abuse postmaster/) {
      # make this easier to search for
      my $FROM = sprintf('smoke.tester+%d@%s', time, $BIND_DOMAIN);
      my $TO   = sprintf('%s@%s', $lp, $BIND_DOMAIN);

      my $msg = MIME::Lite->new(
        From    => $FROM,
        To      => $TO,
        Subject => sprintf('%s %s test INBOUND-01 %s', $C->{subdomain}, $BIND_NAME, time),
        Type    => 'multipart/alternative',
      );

      $msg->attach(
        Type => 'TEXT',
        Data => sprintf("Hi %s,\nSmoke test email from Message Systems!\nTest link: http://www.messagesystems.com\nSmoke Tester", $lp),
      );

      $msg->attach(
        Type => 'text/html',
        Data => sprintf(qq'<p>Hi \%s<br/>\nSmoke test email from Message Systems!<br/>\nTest Link: <a href="http://www.messagesystems.com">messagesystems.com</a><br/>\n</p><p>Smoke Tester</p>', $lp),
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
      # detect connection failure
      if (not $smtp) {
        printf "ERROR: connection to [%s] failed\n", $MX;
        next;
      }

      my $smtp_rc = $smtp->mail($FROM);
      if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
        printf "ERROR: MAIL FROM [%s] failed!\n", $FROM;
        next;
      }

      $smtp_rc = $smtp->to($TO);
      if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
        printf "ERROR: RCPT TO [%s] failed! (%s)\n", $TO, $FROM;
        next;
      }

      $smtp_rc = $smtp->data($msg_str);
      if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
        print "ERROR: DATA failed!\n";
        next;
      }

      printf STDERR "NOTICE: from (%s) to (%s@%s)\n", $FROM, $lp, $BIND_DOMAIN;

      ## the rcpt_to gets magically rewritten with the alias module,
      ## so we need to look for a different address than what we inject
      #my $rcpt_to = sprintf('%s@%s', $lp, $BIND_DOMAIN);
      #my $rcpt_to_regex = qr/^(?:abuse|postmaster)\@/;
      #my $e = $IN->events_with_rcpt_to({
      #  rcpt_to => $rcpt_to_regex,
      #  msg_from => $FROM,
      #  total_elapsed => 150,
      #});

      ## we expect both an injection and delivery
      #my $injections = $IN->count_events_by_rcpt_to($e, {
      #  rcpt_to => $rcpt_to_regex,
      #  msg_from => $FROM,
      #  event_type => 'injection',
      #});
      #if ($injections != 1) {
      #  printf STDERR "ERROR: unexpected value %d for injection! (%s)\n",
      #    $injections, $rcpt_to;
      #} else {
      #  printf STDERR "NOTICE: injection event found for %s\n", $rcpt_to;
      #}

      #my $deliveries = $IN->count_events_by_rcpt_to($e, {
      #  rcpt_to => $rcpt_to_regex,
      #  msg_from => $FROM,
      #  event_type => 'delivery',
      #});
      #if ($deliveries != 1) {
      #  printf STDERR "ERROR: unexpected value %d for delivery! (%s)\n",
      #    $deliveries, $rcpt_to;
      #} else {
      #  printf STDERR "NOTICE: delivery event found for %s\n", $rcpt_to;
      #}

    }
  }
}

