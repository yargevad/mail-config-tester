package Msys::Smoke::Transmission;
use strict;
=cut
DEPRECATED - Msys::API::v1::Transmission is a drop-in replacement for this module
=cut
use JSON;
use Exporter;
our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/
  add_recipient
  default_transmission_json
/;

my $J = JSON->new()->ascii();
my $tjson = undef;

sub add_recipient {
  my ($j, %args) = @_;
  my $add = {
    'address' => {
      'name' => 'Smoke Tester'
    },
    'metadata' => {
      'place' => 'Message Systems'
    },
    'substitution_data' => {
      'customer_type' => 'Platinum',
    }
  };

  for my $key (qw/email name header_to/) {
    if ($args{ $key }) {
      $add->{address}{ $key } = $args{ $key };
    }
  }

  if ($args{metadata} and ref($args{metadata}) eq 'HASH') {
    for my $k (keys %{ $args{metadata} }) {
      $add->{metadata}{ $k } = $args{metadata}{ $k };
    }
  }
  if ($args{substitution_data} and ref($args{substitution_data}) eq 'HASH') {
    for my $k (keys %{ $args{substitution_data} }) {
      $add->{substitution_data}{ $k } = $args{substitution_data}{ $k };
    }
  }

  if (not $j or ref($j) ne 'HASH') {
    warn "expected a hash reference";
    return undef;
  } elsif (not $j->{recipients} or ref($j->{recipients}) ne 'ARRAY') {
    warn "expected an array reference for key 'recipients'";
    return undef;
  }

  push @{ $j->{recipients} }, $add;
  return $add;
}

sub default_transmission_json {
  my (%args) = @_;
  # encode, then decode for a deep copy
  my $json = $J->encode($tjson);
  $json = $J->decode($json);

  if ($args{bind_domain}) {
    $json->{return_path} = sprintf('%s@%s',
      ($args{return_path_localpart} or 'bounces-msys-smoke-test'),
      $args{bind_domain});
  }

  if ($args{mail_from}) {
    $json->{content}{from}{email} = $args{mail_from};
    $json->{content}{from}{name} = ($args{mail_from_friendly} or 'Smoke Tester');
    $json->{content}{reply_to} = sprintf('%s <%s>',
      ($args{reply_to_friendly} or 'Smoke Tester'),
      $args{mail_from});
  }

  if ($args{subject}) {
    $json->{content}{subject} = $args{subject};
  }

  if ($args{headers} and ref($args{headers}) eq 'HASH') {
    for my $hname (keys %{ $args{headers} }) {
      $json->{content}{headers}{ $hname } = $args{headers}{ $hname };
    }
  }

  return $json;
}


$tjson = {
  'options' => {
    'open_tracking' => JSON::true,
    'click_tracking' => JSON::true
  },

  'campaign_id' => 'msys_smoke_test',
  'return_path' => undef,

  'metadata' => {
    'user_type' => 'testers'
  },

  'substitution_data' => {
    'sender' => 'Smoke Tester'
  },

  'recipients' => [],

  'content' => {
    'from' => {
      'name' => undef,
      'email' => undef,
    },
    'subject' => undef,
    'reply_to' => undef,
    'headers' => { },
    'text' => qq'Hi {{address.name}}\nTest email from {{place}}!\nTest link: http://www.messagesystems.com\nUser type: {{user_type}}\n{{sender}}',
    'html' => qq'<p>Hi {{address.name}}<br/>\nTest email from {{place}}!<br/>\nTest link: <a href="http://www.messagesystems.com">messagesystems.com</a><br/></p>\n<p>User type: {{user_type}}</p><br/>\n<p>{{sender}}</p>'
  }
};


1;

