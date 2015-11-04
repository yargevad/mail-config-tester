package Msys::API::v1::Base;
use strict;

use Carp;
use JSON;
use URI::Escape;
use LWP::UserAgent;
use HTTP::Request::Common qw/GET PUT POST DELETE/;

use Msys::Smoke::Config;

# Attempt to load a cert bundle that allows us to verify remote certs.
our $HAVE_MOZILLA_CA = undef;
BEGIN {
  eval "use Mozilla::CA;";
  if ($@) {
    warn "Mozilla::CA unavailable, will not verify remote certificates.";
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
  } else {
    $HAVE_MOZILLA_CA = 1;
  }
}

sub new {
  my $class = shift;
  my ($self, %args) = ({}, @_);
  # TODO: more automatic api_base handling based on type
  # TODO: pass in only the part of the URL that changes from API to API
  if (not $args{config}) {
    warn sprintf("must specify 'config' to constructor %s", $class);
    return undef;
  }
  my $api_type = $args{type} || $args{config}{type};
  if ($api_type eq 'elite' or $api_type eq 'sparkpost' or $api_type eq 'onprem') {
    if (not $args{api_path}) {
      warn sprintf("'api_path' is required for type '%s' (%s)",
        $api_type, $class);
      return undef;
    }
    if ($api_type eq 'onprem' and not $args{config}{api_base}) {
      warn sprintf("'api_base' is required for type '%s' (%s)",
        $api_type, $class);
      return undef;
    }
    $self->{api_base} = $args{config}->api_base($args{api_path});

  } elsif ($api_type eq 'adhoc') {
    if (not $args{api_base}) {
      warn "api_base is required for 'adhoc' api modules";
      return undef;
    }

  } else {
    confess(sprintf('Unexpected type [%s]', $api_type));
  }
  bless $self, $class;
  my $ua = $self->{_ua} = LWP::UserAgent->new(
    # Only request hostname verification if Mozilla::CA is available
    $HAVE_MOZILLA_CA ? (
      ssl_opts => { verify_hostname => 1 },
      SSL_ca_file => Mozilla::CA::SSL_ca_file(),
    ) : ()
  );

  my $cfg = undef;
  # we want to send the configured api key for all types except 'adhoc'
  if ($api_type eq 'elite' or $api_type eq 'sparkpost' or $api_type eq 'onprem') {
    $ua->default_header('Authorization' => $args{config}{api_key});
  }

  $ua->default_header('Content-Type' => 'application/json');
  if ($args{LWP_DEBUG}) {
    # extreme debug
    $ua->add_handler("request_send",  sub { shift->dump; return });
    $ua->add_handler("response_done", sub { shift->dump; return });
  }
  $self->{_json} = JSON->new()->ascii();

  for my $key (keys %args) {
    $self->{$key} = $args{$key} if not exists $self->{$key};
  }
  return $self;
}

sub _got_json {
  my ($self, $res) = (shift, shift);
  my $ctype = $res->header('Content-Type');
  if ($ctype !~ /^application\/json\b/) {
    printf STDERR "ERROR: expected JSON, got [%s]\n", $ctype;
    return 0;
  }
  return 1;
}

sub last_error {
  my ($self, $err) = (shift, shift);
  if (not $err) {
    return $self->{_last_error};
  }
  $self->{_last_error} = $err;
}

sub get_entries {
  my $self = shift;
  my $params = shift;
  $self->last_error(); # reset
  my $url = sprintf('%s/', $self->{api_base});
  # query parameters
  if ($params and ref($params) eq 'HASH' and scalar(keys(%$params))) {
    my $qstr = join('&',
      map(sprintf('%s=%s',
          uri_escape($_),
          uri_escape($params->{$_})),
        keys(%$params)));
    $url = sprintf('%s?%s', $url, $qstr);
  }

  my $res = $self->{_ua}->request(GET $url);
  if ($res->code() != 200) {
    $self->last_error(sprintf("GET %s\n%s", $url, $res->as_string()));
    return undef;
  } else {
    if (not $self->_got_json($res)) {
      $self->last_error(sprintf("GET %s\n%s", $url, $res->as_string()));
      return undef;
    }
    return $self->{_json}->decode( $res->content() );
  }
}

sub get_entry {
  my ($self, $id, $params) = @_;
  $self->last_error(); # reset
  my $enc = uri_escape($id);
  my $url = sprintf('%s/%s', $self->{api_base}, $enc);
  # query parameters
  if ($params and ref($params) eq 'HASH' and scalar(keys(%$params))) {
    my $qstr = join('&',
      map(sprintf('%s=%s',
          uri_escape($_),
          uri_escape($params->{$_})),
        keys(%$params)));
    $url = sprintf('%s?%s', $url, $qstr);
  }

  my $res = $self->{_ua}->request(GET $url);
  if ($res->code() != 200) {
    $self->last_error(sprintf("GET %s\n%s", $url, $res->as_string()));
    return undef;
  } else {
    if (not $self->_got_json($res)) {
      $self->last_error(sprintf("GET %s\n%s", $url, $res->as_string()));
      return undef;
    }
    return $self->{_json}->decode( $res->content() );
  }
}

sub put_entry {
  my ($self, $id, $args) = @_;
  $args->{_id} = $id;
  $args->{_method} = 'PUT';
  return $self->put_post_entry($id, $args);
}

sub post_entry {
  my ($self, $args) = @_;
  $args->{_method} = 'POST';
  return $self->put_post_entry($args);
}

sub put_post_entry {
  my ($self, $args) = @_;
  $self->last_error(); # reset
  my $url = $self->{api_base};
  if (not $url) {
    warn "got a blank url";
    return undef;
  }
  my $json = $args->{json}
    ? $self->{_json}->encode($args->{json})
    : undef;

  my $res = undef;
  if (uc($args->{_method}) eq 'PUT') {
    my $enc = uri_escape($self->{_id});
    $url = sprintf('%s/%s', $self->{api_base}, $enc);
    # TODO: handle case where both content and content_type are supplied (see below)
    $res = $self->{_ua}->request(
      PUT $url,
      # Only send Content if we got JSON from our caller
      $json ? (Content => $json) : (),
    );

  } elsif (uc($args->{_method}) eq 'POST') {
    if ($json) {
      $res = $self->{_ua}->request(
        POST $url,
        # POST happily overrides the default Content-Type we set, above
        'Content-Type' => 'application/json',
        $json ? (Content => $json) : (),
      );
    } else {
      # use supplied values for both content and content_type
      $res = $self->{_ua}->request(
        POST $url,
        ($args->{content_type} ? ('Content-Type' => $args->{content_type}) : ()),
        Content => $args->{content},
      );
    }

  } else {
    warn sprintf("unsupported method [%s]!", $args->{_method});
    return undef;
  }

  if ($res->code() != 200) {
    $self->last_error(sprintf("%s %s\n%s", $args->{_method}, $url, $res->as_string()));
    return undef;
  } else {
    if (not $self->_got_json($res)) {
      $self->last_error(sprintf("%s %s\n%s", $args->{_method}, $url, $res->as_string()));
      return undef;
    }
    my $c = $res->content();
    # sigh
    if (ref($self) eq 'Msys::Smoke::Validator') {
      if ($c eq '"No test results found"') {
        return undef;
      }
    }
    return $self->{_json}->decode( $res->content() );
  }
}

sub delete_entry {
  my ($self, $id) = @_;
  $self->last_error(); # reset
  my $url = $self->{api_base};
  if ($id) {
    my $enc = uri_escape($id);
    $url = sprintf('%s/%s', $url, $enc);
  }
  my $res = $self->{_ua}->request(DELETE $url);

  if ($self->{DEBUG}) {
    printf STDERR "DELETE %s\n", $url;
    printf STDERR "HTTP %d\n", $res->code();
  }

  my $rc = $res->code();
  if ($rc != 204 and $rc != 200) {
    $self->last_error(sprintf("DELETE %s\n%s", $url, $res->as_string()));
    return undef;
  } else {
    # no content on success, decode and return array with the id that was removed
    return { id => $id };
  }
}


1;

