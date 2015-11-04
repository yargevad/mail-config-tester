#!/usr/bin/env perl
# vim:syntax=perl:
use strict;
use local::lib;

use lib './lib';
use Msys::API::v1::MessageEvents;
use Msys::Smoke::DNS 'mx_get';
use Msys::Smoke::Config 'load_test_config';

use Net::SMTPS;
use MIME::Lite;
use MIME::Base64 'encode_base64';

my $SSL  = 'undef'; # starttls / ssl / undef

my $C = load_test_config();
my $ME = Msys::API::v1::MessageEvents->new(config => $C);

my $BIND_NAME = $C->random_binding();
my $DOMAINS = $C->binding_domains($BIND_NAME);

for my $BIND_DOMAIN (@$DOMAINS) {
  my $FROM = sprintf('smoke.tester+%d@%s', time, $BIND_DOMAIN);
  my $TO   = sprintf('inbound@%s', $BIND_DOMAIN);

  my $msg = MIME::Lite->new(
    From    => $FROM,
    To      => $TO,
    Subject => sprintf('%s %s test INBOUND-04 %s', $C->{subdomain}, $BIND_NAME, time),
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

  my $smtp_rc = $smtp->mail($FROM);
  if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
    printf "ERROR: MAIL FROM [%s] failed!\n", $FROM;
    exit(1);
  }

  $smtp_rc = $smtp->to($TO);
  if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
    printf "ERROR: RCPT TO [%s] failed (%s)\n", $TO, $FROM;
    exit(1);
  }

  $smtp_rc = $smtp->data($msg_str);
  if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
    print "ERROR: DATA failed!\n";
    exit(1);
  }

  printf "NOTICE: injected from (%s) to (%s)\n", $FROM, $TO;
  # TODO: get final disposition of message using:
  #   msg_from (friendly_froms)
  #   rcpt_to (recipients)
}

