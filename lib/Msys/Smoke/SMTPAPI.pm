package Msys::Smoke::SMTPAPI;
use strict;

use JSON;
use Exporter;
use MIME::Lite;
use Net::SMTPS;
use Capture::Tiny 'capture';

use lib './lib';

our @ISA = ('Exporter');
our @EXPORT_OK = qw/
  build_smtpapi_message
  default_smtpapi_json
/;

my $J = JSON->new()->ascii();
my $sjson = undef;

# make sure there is whitespace in our generated json, so it can be
# safely folded into a multi-line header:
# https://support.messagesystems.com/docs/web-momo4/x-msys-api_header.php
$J->space_before(1);
$J->space_after(1);

# TODO: wrapper for this package and Transmission API
# chooses which types of injection to use based on client type, or specific config
# when more than one protocol is available, specify with
# _test_protocol = smtp

sub new {
  my $class = shift;
  my ($self, %args) = ({}, @_);
  if (not $args{config}) {
    warn sprintf("must specify 'config' to constructor %s", $class);
    return undef;
  }
  $self->{$_} = $args{$_} for keys %args;
  bless $self, $class;
  return $self;
}

sub inject {
  my ($self, %args) = @_;
  my $C = $self->{config};
  my $smtp_host = $C->{smtp_host}; # FIXME: sane default?
  if (not $smtp_host) {
    warn "no smtp host configured, cannot deliver";
    return undef;
  }

  if (not $args{mail_from}) {
    warn "no `mail_from` specified, must set a sender";
    return undef;
  } elsif (not $args{rcpt_to}) {
    warn "no `rcpt_to` specified, must set a recipient";
    return undef;
  } elsif (not $args{msg}) {
    warn "no `msg` specified, can't send nothing";
    return undef;
  }

  my ($stdout, $stderr, @results) = capture {
    my $smtp_port = $C->{smtp_port} || 587;
    my $smtp = Net::SMTPS->new(
      $smtp_host,
      Port => $smtp_port,
      doSSL => 'starttls',
      Debug => 1, # always get debug info, only display if needed
      Timeout => ($self->{timeout} || 10),
    );
    if (not $smtp) {
      warn sprintf("connection to %s:%s failed", $smtp_host, $smtp_port);
      return undef;
    }

    # for SPE or SparkPost, auth with api key
    # for on-prem, auth if configured, otherwise assume we're in Relay_Hosts
    my ($type, $rv) = ($C->{type}, undef);
    if ($type eq 'elite' or $type eq 'sparkpost' or ($type eq 'onprem' and $C->{smtp_user})) {
      my $pass = ($type eq 'onprem') ? $C->{smtp_pass} : $C->{api_key};
      return undef if not $smtp->auth(($C->{smtp_user} || 'SMTP_Injection'), $pass);
    }

    return undef if not $smtp->mail($args{mail_from});
    return undef if not $smtp->to($args{rcpt_to});

    my $msg_str = $args{msg}->as_string();
    $msg_str =~ s/\r?\n/\r\n/g;
    return undef if not $smtp->data( [ $msg_str ] );

    return 1;
  };

  if (not $results[0]) {
    $self->{_stderr} = $stderr;
    return undef;
  } elsif ($self->{debug}) {
    printf STDERR $stderr;
  }

  return 1;
}

sub build_smtpapi_message {
  my (%args) = @_;
  # this is what we'll pass to MIME::Lite->new
  my %ml_args = ();

  if ($args{bind_domain}) {
    $ml_args{'Return-Path'} = sprintf('%s@%s',
      ($args{return_path_localpart} or 'bounces-msys-smoke-test'),
      $args{bind_domain});
  } else {
    warn "no `bind_domain` specified, needed for Return-Path";
    return undef;
  }

  if ($args{mail_from}) {
    $ml_args{From} = sprintf('%s <%s>',
      ($args{mail_from_friendly} or 'Smoke Tester'),
      $args{mail_from});
    $ml_args{'Reply-To'} = sprintf('%s <%s>',
      ($args{reply_to_friendly} or 'Smoke Tester'),
      $args{mail_from});
  } else {
    warn "no `mail_from` specified, must set a sender";
    return undef;
  }

  if ($args{rcpt_to}) {
    $ml_args{To} = sprintf('%s <%s>',
      ($args{rcpt_to_friendly} or 'Test Recipient'),
      $args{rcpt_to});
  } else {
    warn "no `rcpt_to` specified, must set a recipient";
    return undef;
  }

  if ($args{subject}) {
    $ml_args{Subject} = $args{subject};
  } else {
    $ml_args{Subject} = sprintf('This is a test message %d', time);
  }

  my $json = undef;
  if ($args{x_msys_api}) {
    $json = $args{x_msys_api};
  } else {
    $json = default_smtpapi_json();
  }

  if ($args{metadata} and ref($args{metadata}) eq 'HASH') {
    for my $mname (keys %{ $args{metadata} }) {
      $json->{metadata}{ $mname } = $args{metadata}{ $mname };
    }
  }

  $ml_args{'X-MSYS-API'} = $J->encode($json);

  if ($args{headers} and ref($args{headers}) eq 'HASH') {
    for my $hname (keys %{ $args{headers} }) {
      $ml_args{ $hname } = $args{headers}{ $hname };
    }
  }

  my $msg = MIME::Lite->new(
    %ml_args,
    Type => 'multipart/alternative',
  );

  $msg->attach(
    Type => 'TEXT',
    Data => sprintf("Hi there,\nSmoke test email from Message Systems!\nTest link: http://www.messagesystems.com\nSmoke Tester", $ENV{USER}),
  );

  $msg->attach(
    Type => 'text/html',
    Data => sprintf(qq'<p>Hi \%s<br/>\nSmoke test email from Message Systems!<br/>\nTest Link: <a href="http://www.messagesystems.com">messagesystems.com</a><br/>\n</p><p>Smoke Tester</p>', $ENV{USER}),
  );

  my $rv = {
    msg => $msg,
    mail_from => $args{mail_from},
    rcpt_to => $args{rcpt_to},
  };
  return $rv;
}

sub default_smtpapi_json {
  my (%args) = @_;
  # encode, then decode for a deep copy
  my $json = $J->encode($sjson);
  $json = $J->decode($json);

  # default these to ON, turn off if specifically requested
  if ($args{click_tracking} =~ /false/i) {
    $json->{options}{click_tracking} = JSON::false;
  }
  if ($args{open_tracking} =~ /false/i) {
    $json->{options}{open_tracking} = JSON::false;
  }

  if ($args{metadata} and ref($args{metadata}) eq 'HASH') {
    for my $key (%{ $args{metadata} }) {
      $json->{metadata}{ $key } = $args{metadata}{ $key };
    }
  }

  return $json;
}


$sjson = {
  campaign_id => 'msys_smoke_test',
  metadata => {
    user_type => 'testers',
  },
  options => {
    click_tracking => JSON::true,
    open_tracking => JSON::true,
  },
  tags => [],
};

# example usage
if (not caller()) {
  require Msys::Smoke::Config;
  my $C = Msys::Smoke::Config::load_test_config();
  my $data = build_smtpapi_message(
    bind_domain => 'messagesystems.com',
    mail_from => 'dgray@messagesystems.com',
    rcpt_to => 'dgray@messagesystems.com',
  );

  my $s = Msys::Smoke::SMTPAPI->new(
    config => $C,
    debug => 1,
  );
  if (not $s->inject(%$data)) {
    printf "ERROR: failed to inject\n%s", $s->{_stderr};
  }
}

1;

