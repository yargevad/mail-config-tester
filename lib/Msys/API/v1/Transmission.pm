package Msys::API::v1::Transmission;
use strict;

use Carp;
use JSON;
use Exporter;

use lib './lib';
use Msys::API::v1::Base;
our @ISA = ('Msys::API::v1::Base', 'Exporter');
our @EXPORT_OK = qw/
  add_recipient
  replace_recipient
  default_transmission_json
/;

my $J = JSON->new()->ascii();
my $tjson = undef; # populated below

sub new {
  my $class = shift;
  my $tr = $class->SUPER::new(
    api_path => 'transmissions',
    @_,
  );
  return $tr;
}

sub post_entry {
  my ($self, $hr) = @_;
  my $res = $self->SUPER::post_entry({ json => $hr });
  if (not $res) {
    return (undef, $self->last_error());
  }
  return $res;
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

sub replace_recipient {
  my $j = $_[0];
  $j->{recipients} = [];
  goto &add_recipient;
}

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
    warn sprintf("expected a hash reference, got:\n%s", $j);
    return undef;
  } elsif (not $j->{recipients} or ref($j->{recipients}) ne 'ARRAY') {
    warn "expected an array reference for key 'recipients'";
    return undef;
  }

  push @{ $j->{recipients} }, $add;
  return $add;
}


1;

