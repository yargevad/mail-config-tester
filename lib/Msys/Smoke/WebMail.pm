package Msys::Smoke::WebMail;
use strict;

use Mail::IMAPClient;
use Email::MIME;

use Msys::Smoke::Config;

our $RC = '.webmailrc';

our %_servers = (
  outlook => 'imap-mail.outlook.com',
  yahoo   => 'imap.mail.yahoo.com',
  gmail   => 'imap.gmail.com',
  aol     => 'imap.aol.com',
);

sub new {
  my $class = shift;
  my ($self, %args) = ({}, @_);
  bless $self, $class;
  for my $key (keys %args) {
    $self->{$key} = $args{$key} if not exists $self->{$key};
  }
  my $W = $self->{_cfg} = Msys::Smoke::Config::read_config($RC);

  # choose a random recipient, if not specified
  if ($self->{type} and not $self->{rcpt_to}) {
    if (not $W->{ lc($self->{type}) }) {
      die sprintf("Invalid email type [%s]!", $self->{type});
    }
    $self->{rcpt_to} = $W->{ lc($self->{type}) }{user};
  } elsif (not $self->{rcpt_to}) {
    ($self->{type}, $self->{rcpt_to}) = random_rcpt_to($W);
  }

  if (not $self->{type}) {
    if (not $self->{rcpt_to}) {
      die "'type' or 'rcpt_to' must be provided!";
    }
    # auto-detect account type from domain
    if (not ($self->{type} = $self->detect_type($self->{rcpt_to}))) {
      die sprintf("account type not detected for %s", $self->{rcpt_to});
    }
  }
  my $type = lc($self->{type});
  if (not $_servers{$type}) {
    die "unsupported webmail type '$type'! (server)"
  }
  if (not $W->{ $type }) {
    die "unsupported webmail type '$type'! (config)";
  }
  my $wc = $W->{ $type };
  $self->{_imap_args} = {
    Server   => $_servers{$type},
    User     => $wc->{user},
    Password => $wc->{pass},
    Ssl      => 1,
    $self->{debug} ? (Debug => 1) : (),
  };
  return $self;
}

sub imap_connect {
  my $self = shift;
  my $I = $self->{_imap} = Mail::IMAPClient->new(%{ $self->{_imap_args} });
  if (not $I or $I->LastError()) {
    die sprintf("imap connection to %s failed: %s",
      $_servers{ $self->{type} }, $@);
  }
}

sub random_rcpt_to {
  my $cfg = shift;
  if (not $cfg or ref($cfg) ne 'HASH' or not scalar(keys(%$cfg))) {
    die sprintf("random_rcpt_to: no webmail config, check [%s]", $RC);
  }
  my @valid = grep(/^(?:gmail|yahoo|outlook|aol)$/i, keys(%$cfg));
  my $idx = int(rand(scalar(@valid)));
  my $email = $cfg->{ $valid[$idx] }{user};
  return ($valid[$idx], $email);
}

sub detect_type {
  my ($self, $addr) = @_;
  my ($lp, $dom) = split('@', $addr);
  if ($dom eq 'gmail.com') {
    return 'gmail';
  } elsif ($dom eq 'yahoo.com') {
    return 'yahoo';
  } elsif ($dom eq 'outlook.com') {
    return 'outlook';
  } elsif ($dom eq 'aol.com') {
    return 'aol';
  }
  return undef;
}

sub list_folders {
  my ($self) = shift;
  my $I = $self->{_imap};
  if (not $I) {
    die "need an imap connection to get folders!";
  }
  my $folders = $I->folders();
  if ($I->LastError()) {
    die sprintf("Couldn't list folders: %s", $I->LastError());
  }
  my $rv = [];
  for my $folder (@$folders) {
    # we only care about inbox and spam
    next if $folder !~ /^inbox$/i and $folder !~ /\b(?:spam|bulk|junk)\b/i;
    push @$rv, $folder;
  }
  return $rv;
}

sub select_folder {
  my ($self, $folder) = @_;
  my $I = $self->{_imap};
  if (not $I) {
    die "need an imap connection to select a folder!";
  }
  $I->select($folder);
  if ($I->LastError()) {
    die sprintf("Couldn't select folder (%s): %s", $folder, $I->LastError());
  }
  return 1;
}

sub folder_subject_lines {
  my ($self) = shift;
  my $I = $self->{_imap};
  if (not $I) {
    die "need an imap connection to get subject lines!";
  }
  my $res = $I->fetch('ALL', 'BODY.PEEK[HEADER.FIELDS (SUBJECT)]');
  if ($I->LastError()) {
    die sprintf("Couldn't fetch headers: %s", $I->LastError());
  }

  my $res_header = shift(@$res);
  my $res_footer = pop(@$res);

  # ugh. how is there not a method to parse these results?
  my %msgs = ();
  # line-oriented processing of results array
  MESSAGE:
  while (scalar(@$res)) {
    my ($header, $idx, $uid) = (undef, undef, undef);
    HEADERLINE: do {
      $header = shift(@$res);
      if ($header =~ /
        ^           # beginning of line
        [ *]        # space or *
        \s+
        (\d+)       # capture integer index
        \s+
        FETCH
        \s+
        \(          # literal open paren
          (?:       # begin optional group
            FLAGS
            \s+
            \(.*?\) # literal paren group
            \s+
          )?        # end optional group
          UID
          \s+
          (\d+)     # capture uid
      /x) {
        ($idx, $uid) = ($1, $2);
      } else {
        # ugly attempt to fix unexpected line we get occasionally
        if ($header =~ /^\*\s+\d+\s+EXISTS\b/) {
          next HEADERLINE;
        }
        die "unexpected format for IMAP header:\n$header\n";
      }
    } while (0);

    my $subject = shift(@$res);
    $subject =~ s/\s+$//;
    if (not $subject =~ s/^subject:\s*//i) {
      die "unexpected format for Subject header:\n$subject\n";
    }

    my $close = shift(@$res);
    if ($close !~ /^\s*\)\s*$/) {
      die "unexpected format for IMAP result block:\n$close\n";
    }

    $msgs{$subject} = {
      index => $idx,
      uid => $uid,
    };

  }
  return \%msgs;
}

sub rfc822_for_uid {
  my ($self, $uid) = @_;
  my $I = $self->{_imap};
  if (not $I) {
    die "need an imap connection to get mime!";
  }
  my $res = $I->fetch($uid, 'BODY[]');
  if ($I->LastError()) {
    die sprintf("Couldn't get [%s] body: %s", $uid, $I->LastError());
  }
  my ($body_header, $body_footer) = (shift(@$res), pop(@$res));
  my ($msg_header, $msg_footer) = (shift(@$res), pop(@$res));
  return $res->[0];
}

sub message_with_subject {
  my ($self, $subject) = (shift, shift);
  my %args = @_;
  my $folders = $self->list_folders();
  for my $f (@$folders) {
    $self->select_folder($f);
    my $subs = $self->folder_subject_lines();
    if ($args{debug}) {
      require Data::Dumper;
      printf STDERR "[%s]:\n%s", $subject, Data::Dumper->Dump([$subs], ['SUBJECTS']);
    }
    if ($subs->{ $subject }) {
      my $rv = {};
      $rv->{folder} = $f;
      $rv->{rfc822} = $self->rfc822_for_uid($subs->{ $subject }{uid});
      return $rv;
    }
  }
  return undef;
}

sub wait_for_messages {
  my ($self, %args) = @_;
  my $pause = $args{pause} || 2; # seconds
  die "`pause` must be an integer" if $pause =~ /\D/;
  my $tries = $args{tries} || 15;
  die "`tries` must be an integer" if $tries =~ /\D/;
  my $sub = $args{subject};
  if (not $sub) {
    die "wait_for_messages: need a subject line to search for!";
  }

  my $i = 0;
  while (1) {
    my $msg = $self->message_with_subject($sub);
    if (not $msg) {
      printf STDERR "waiting %ds for [%s]...\n", $pause, $sub;
      sleep($pause);
      if (++$i >= $tries) {
        die sprintf("stopped waiting for [%s] after %ds.", $sub, $pause * $tries);
      }
      next;
    }

    if ($msg->{folder} !~ /^inbox$/i) {
      die sprintf("(%s): [%s] to [%s]", $msg->{folder}, $sub, $self->{rcpt_to});
    }
    $self->{_msg} = $msg;
    return $msg;
  }
}

sub headers_from_message {
  my ($self, $msg) = (shift, shift);
  my $msg ||= $self->{_msg};
  my %headers = map((lc($_) => 1), @_);
  my $mime = $msg->{mime} || ($msg->{mime} = Email::MIME->new($msg->{rfc822}));
  # always get these headers - specify any others as function parameters
  for my $h (qw/
    to from subject
    return-path reply-to
    authentication-results dkim-signature received-spf
    x-msfbl message-id x-binding
  /) {
    $headers{$h} = 1;
  }
  for my $h (keys(%headers)) {
    $headers{$h} = [ $mime->header($h) ];
  }
  $msg->{headers} = \%headers;
  return \%headers;
}

sub header_as_string {
  my ($self, $name) = @_;
  my $h = $self->{_msg}{headers}{ lc($name) };
  if ($h and ref($h) eq 'ARRAY') {
    return join('', map(sprintf("%s: %s\r\n", $name, $_), @$h));
  }
  return undef;
}

=cut
Gmail:
Authentication-Results: mx.google.com;
       spf=pass (google.com: domain of bounces-msys-smoke-test@explore.pinterest.com designates 54.149.191.242 as permitted sender) smtp.mail=bounces-msys-smoke-test@explore.pinterest.com;
       dkim=pass header.i=@explore.pinterest.com;
       dmarc=pass (p=REJECT dis=NONE) header.from=pinterest.com
Received-SPF: pass (google.com: domain of bounces-msys-smoke-test@e.ebates.com designates 52.11.191.239 as permitted sender) client-ip=52.11.191.239;

Yahoo!:
Authentication-Results: mta1214.mail.ne1.yahoo.com  from=e.ebates.com; domainkeys=neutral (no sig);  from=e.ebates.com; dkim=pass (ok)
Received-SPF: pass (domain of e.ebates.com designates 52.11.191.239 as permitted sender)

Outlook:
Authentication-Results: hotmail.com; spf=pass (sender IP is 54.149.191.244; identity alignment result is pass and alignment mode is relaxed) smtp.mailfrom=bounces-msys-smoke-test@info.pinterest.com; dkim=pass (identity alignment result is pass and alignment mode is relaxed) header.d=info.pinterest.com; x-hmca=pass header.id=smoke.tester@info.pinterest.com
-- NO Received-SPF header

AOL:
Authentication-Results: mx.aol.com; spf=pass (aol.com: the domain e.ebates.com reports 52.11.191.239 as a permitted sender.) smtp.mailfrom=e.ebates.com; dkim=pass (aol.com: email passed verification from the domain e.ebates.com.) header.d=e.ebates.com;
X-AOL-SPF: domain : e.ebates.com SPF : pass
=cut

sub parse_auth_headers {
  my ($self, $msg) = (shift, shift);
  if (not $msg->{headers}) { die "no message headers!" }
  if (not scalar(@{ $msg->{headers}{'authentication-results'} || [] })
      or not $msg->{headers}{'authentication-results'}[0]
  ) {
    die "no authentication-results header!"
  }
  my $ar = $msg->{headers}{'authentication-results'}[0];
  my %auth = (auth=>$ar);
  while ($ar =~ /((?:spf|dkim|dmarc))=(\w+)/ig) {
    $auth{$1} = $2;
  }

  if ($self->{type} eq 'gmail') {
    if ($ar =~ /\bdesignates?\s+(\d+\.\d+\.\d+\.\d+)\s+/) {
      $auth{ip} = $1;
    }
  } elsif ($self->{type} eq 'outlook') {
    if ($ar =~ /\bsender\s+IP\s+is\s+(\d+\.\d+\.\d+\.\d+);/) {
      $auth{ip} = $1;
    }
  } elsif ($self->{type} eq 'aol') {
    if ($ar =~ /\breports\s+(\d+\.\d+\.\d+\.\d+)\s+as\s+a\s+permitted\b/) {
      $auth{ip} = $1;
    }
  } elsif ($self->{type} eq 'yahoo') {
    # check Received-SPF for SPF status and IP
    my $spf = $msg->{headers}{'received-spf'}[0];
    if ($spf =~ /^(\w+)\s+\(domain\s+of\s+.*?\bdesignates\s+(\d+\.\d+\.\d+\.\d+)\s+as/) {
      ($auth{spf}, $auth{ip}) = ($1, $2);
    }
  }

  return \%auth;
}

sub assert_auth {
  my ($self, $parsed, $conf) = @_;
  my $pass = 1;

  if ($conf->{spf} and not $parsed->{spf}) {
    print STDERR "SPF FAIL:\n";
    if ($self->{type} eq 'outlook') {
      # No Received-SPF header; data is in Authentication-Results
      print STDERR $self->header_as_string('Authentication-Results'), "\n";
    } elsif ($self->{type} eq 'aol') {
      # No Received-SPF header; data is in X-AOL-SPF
      print STDERR $self->header_as_string('X-AOL-SPF'), "\n";
    } elsif ($self->{type} eq 'gmail') {
      print STDERR $self->header_as_string('Received-SPF'), "\n";
    } elsif ($self->{type} eq 'yahoo') {
      # remove the extra data yahoo tacks on the end
      my $h = $self->header_as_string('Received-SPF');
      $h =~ s/\).*$/)/s;
      print STDERR $h, "\n";
    }
    $pass = 0;
  }

  if ($conf->{dkim} and not $parsed->{dkim}) {
    print STDERR "DKIM failure!\n";
    print STDERR $self->header_as_string('DKIM-Signature'), "\n";
    $pass = 0;
  }

  if ($conf->{dmarc} and not $parsed->{dmarc}) {
    print STDERR "DMARC failure!\n";
    print STDERR $self->header_as_string('Authentication-Results'), "\n";
    $pass = 0;
  }

  return $pass;
}

sub assert_headers {
  # TODO: presence of X-MSFBL containing base64-encoded data
  # TODO: presence of List-Unsubscribe header containing mailto
  #       shouldn't we add a link here too?
  # TODO: domain of address in From header matches binding domain
  # TODO: domain of address in Return-Path header matches binding domain
}


1;

