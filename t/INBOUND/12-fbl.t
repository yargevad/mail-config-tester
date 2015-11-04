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

my $C = load_test_config();

my $SSL  = 'undef'; # starttls / ssl / undef

## create a webhook bucket, and then a webhook
#my $IN = Msys::Smoke::WebHookInbox->new();
#$IN->create();
#my $rv = $IN->setup({
#  config => $C,
#  events => [qw/
#    injection delivery bounce delay
#    spam_complaint policy_rejection
#  /],
#});
#if (not defined($rv)) {
#  printf STDERR "ERROR: failed to set up web hook!\n";
#  exit(1);
#}

my $DOMAINS = $C->fbl_domains();
for my $FBL_DOMAIN (@$DOMAINS) {
  for my $lp (qw/fbl FBL/) {
    my $FROM = sprintf('smoke.tester+%d@%s', time, $FBL_DOMAIN);
    my $TO   = sprintf('%s@%s', $lp, $FBL_DOMAIN);
    # FIXME: programmatically build this message with Email::MIME
    my $MIME_BOUNDARY = sprintf('_----%d===_61/00-25439-267B0055', time);

# This message uses an X-MSFBL header pulled from a message to
# dgray@messagesystems.com
my $arf_str = <<ARF_MIME;
From: <$FROM>
Date: Thu, 8 Mar 2005 17:40:36 EDT
Subject: FW: Earn money
To: <$TO>
MIME-Version: 1.0
Content-Type: multipart/report; report-type=feedback-report;
      boundary="$MIME_BOUNDARY"

--$MIME_BOUNDARY
Content-Type: text/plain; charset="US-ASCII"
Content-Transfer-Encoding: 7bit

This is an email abuse report for an email message
received from IP 10.67.41.167 on Thu, 8 Mar 2005
14:00:00 EDT.
For more information about this format please see
http://www.mipassoc.org/arf/.

--$MIME_BOUNDARY
Content-Type: message/feedback-report

Feedback-Type: abuse
User-Agent: SomeGenerator/1.0
Version: 0.1

--$MIME_BOUNDARY
Content-Type: message/rfc822
Content-Disposition: inline

From: <bounces-msys-smoke-test\@$FBL_DOMAIN>
Received: from mailserver.example.net (mailserver.example.net
        [10.67.41.167])
        by example.com with ESMTP id M63d4137594e46;
        Thu, 08 Mar 2005 14:00:00 -0400
To: <Undisclosed Recipients>
Subject: Earn money
MIME-Version: 1.0
Content-type: text/plain
Message-ID: 8787KJKJ3K4J3K4J3K4J3.mail\@$FBL_DOMAIN
X-MSFBL: rhwpKdyGZrTvZJGghHv5u/aHUGfEweJOXKYX38N6LxA=|eyJtZXNzYWdlX2lkIjo
iMDAwMjYyYjcwMDU1NWY2MzE4MDAiLCJ0ZW1wbGF0ZV9pZCI6InRlbXBsYXRlXzQ
3OTkxODE4NTE5ODM4NzI3IiwicmNwdF9tZXRhIjp7InBsYWNlIjoiTWVzc2FnZSB
TeXN0ZW1zIiwidXNlcl90eXBlIjoidGVzdGVycyJ9LCJnIjoiZSIsImIiOiJlMjE
5OCIsInIiOiJkZ3JheUBtZXNzYWdlc3lzdGVtcy5jb20iLCJjdXN0b21lcl9pZCI
6IjEiLCJyY3B0X3RhZ3MiOlsgXSwidHJhbnNtaXNzaW9uX2lkIjoiNDc5OTE4MTg
1MTk4Mzg3MjciLCJjYW1wYWlnbl9pZCI6Im1zeXNfc21va2VfdGVzdCIsInRlbXB
sYXRlX3ZlcnNpb24iOiIwIn0=
Date: Thu, 02 Sep 2004 12:31:03 -0500

Spam Spam Spam
Spam Spam Spam
Spam Spam Spam
Spam Spam Spam

--$MIME_BOUNDARY--
ARF_MIME

    $arf_str =~ s/\r?\n/\r\n/g;

    # auto-detect MX for this domain
    my @mx = mx_get($FBL_DOMAIN);
    if (not scalar(@mx)) {
      printf "ERROR: no MX for domain [%s]\n", $FBL_DOMAIN;
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
      printf "ERROR: RCPT TO [%s] failed! (%s)\n", $TO, $FROM;
      exit(1);
    }

    $smtp_rc = $smtp->data($arf_str);
    if (not $smtp_rc or (ref($smtp_rc) and not scalar(@{ $smtp_rc || [] }))) {
      print "ERROR: DATA failed!\n";
      exit(1);
    }

    printf "NOTICE: from (%s) to: (%s)\n", $FROM, $TO;
    #$IN->{verbose} = 1;
    #my $e = $IN->events_with_rcpt_to({
    #  rcpt_to => $TO,
    #  expected => {
    #    injection => 1,
    #    spam_complaint => 1,
    #    policy_rejection => 1,
    #  },
    #});
  }
}

# confirm FBL reception/processing using rawlog api
# - rejection event showing "processed as FBL message"
# - feedback event "fbtype":"abuse"
# confirm FBL event sent through webhooks

