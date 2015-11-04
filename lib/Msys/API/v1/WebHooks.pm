package Msys::API::v1::WebHooks;
use strict;

use JSON;
use HTTP::Request::Common qw/GET PUT DELETE/;

use lib './lib';
use Msys::API::v1::Base;
our @ISA = ('Msys::API::v1::Base');

# Amount of time to wait after adding a new WebHook.
# The active list is refreshed every 30s, wait 60 to be safe.
our $POST_CREATE_WAIT = 60; # seconds
our $EVENT_TYPES = qr/^(?:message|gen|track|unsubscribe)_event$/;

my %EVENTS = ();
$EVENTS{$_} = 1 for qw/
  delivery
  injection
  policy_rejection
  spam_complaint
  delay
  bounce
  out_of_band
  open
  click
  generation_failure
  generation_rejection
  list_unsubscribe
  link_unsubscribe
/;

sub is_valid_event_type {
  my $class = shift;
  my $event_name = shift;
  return exists($EVENTS{ lc($event_name) });
}

sub valid_event_types {
  return [keys(%EVENTS)];
}

sub new {
  my $class = shift;
  my $wh = $class->SUPER::new(
    api_path => 'webhooks',
    @_,
  );
  return $wh;
}


sub post_entry {
  my ($self, $hr) = @_;
  if (ref($hr) ne 'HASH') {
    warn "post_entry expects a hash reference with keys: (name, target, events)";
    return undef;
  }
  if (not $hr->{name}) {
    warn "post_entry requires a name";
    return undef;
  } elsif (not $hr->{target}) {
    warn "post_entry requires a target";
    return undef;
  } elsif (not $hr->{events} or ref($hr->{events}) ne 'ARRAY') {
    warn "post_entry requires an events array ref";
    return undef;
  }
  for my $e (@{ $hr->{events} }) {
    if (not $EVENTS{ lc($e) }) {
      warn sprintf("unrecognized event type [%s] requested", $e);
      return undef;
    }
  }
  my $res = $self->SUPER::post_entry({ json => $hr });
  if (not $res) {
    warn $self->last_error();
    return undef;
  }
  $self->{_webhook} = $res;
  $self->{_webhook}{target} = $hr->{target};
  printf STDERR "created webhook targeting %s\n", $hr->{target};
  if ($POST_CREATE_WAIT) {
    printf STDERR "waiting %ds for activation...\n", $POST_CREATE_WAIT;
    sleep($POST_CREATE_WAIT);
  }
  return $res;
}

sub delete_entry {
  my ($self, $id) = @_;
  $id ||= $self->{_webhook}{results}{id};
  my $immut = '70b70c80-d71f-11e4-8744-071e3a3597ea';
  if (lc($id) eq $immut) {
    die "tried to remove ebates webhook!";
  }
  delete $self->{_webhook};
  return $self->SUPER::delete_entry($id);
}

sub DESTROY {
  my $self = shift;
  if ($self->{_webhook} and not $self->{_immortal}) {
    printf STDERR "auto-destroying webhook for [%s]\n", $self->{_webhook}{target};
    $self->delete_entry();
  }
}


1;

