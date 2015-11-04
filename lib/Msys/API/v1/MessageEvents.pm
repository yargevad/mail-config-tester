package Msys::API::v1::MessageEvents;
use strict;
=cut
https://www.sparkpost.com/api#/reference/message-events/message-events/search-for-message-events
=cut

use Carp;
use Exporter;
use Data::Dumper;

use Msys::API::v1::Base;
our @ISA = ('Msys::API::v1::Base', 'Exporter');

sub new {
  my $class = shift;
  my $me = $class->SUPER::new(
    api_path => 'message-events',
    @_,
  );
  return $me;
}

# key name mapping to regex for simple validation
# XXX: how are values containing commas dealt with in comma-separated lists?
my $options = {
  bounce_classes => qr/^\d+(?:,\d+)*$/,
  campaign_ids => qr/^[[:print:]]+$/, # TODO? more specific
  events => qr/^\w+(?:,\w+)*$/,
  friendly_froms => qr/^[[:print:]]+$/, # TODO: split on commas, validate with Email::Valid
  from => qr/^\d{4}\-\d\d\-\d\dT\d\d:\d\d$/,
  message_ids => qr/^[0-9a-f-]+(?:,[0-9a-f-]+)*/,
  page => qr/^\d+$/,
  per_page => qr/^\d+$/,
  reason => qr/^[[:print:]]+$/, # TODO? more specific
  recipients => qr/^[[:print:]]+$/, # TODO: split on commas, validate with Email::Valid
  template_ids => qr/^[[:print:]]+$/, # TODO? more specific
  timezone => qr/^\w+\/\w+$/,
  to => qr/^\d{4}\-\d\d\-\d\dT\d\d:\d\d$/,
  transmission_ids => qr/^\d+(?:,\d+)*$/,
};

# only get_entries is used by this module
sub get_entries {
  my ($self, $params) = @_;

  # simple parameter checking
  for my $p (keys %{ $params || {} }) {
    my $o = $options->{ $p };
    if (not $o) {
      $self->last_error(sprintf('unrecognized option [%s]', $p));
      return undef;
    } elsif ($params->{ $p } !~ $o) {
      $self->last_error(sprintf('unexpected value for [%s]', $p));
      return undef;
    }
  }

  return $self->SUPER::get_entries($params);
}

=cut
          'results' => [
                         {
                           'bounce_class' => '25',
                           'type' => 'bounce',
                           'msg_from' => 'smoke.tester+1441401809@c1-t.msyscloud.com',
                           'msg_size' => '1417',
                           'recv_method' => 'esmtp',
                           'reason' => '551 5.7.0 [internal] recipient blackholed',
                           'friendly_from' => 'smoke.tester+1441401809@c1-t.msyscloud.com',
                           'rcpt_to' => 'inbound@c1-t.msyscloud.com',
                           'binding_group' => 'default',
                           'timestamp' => '2015-09-04T21:23:31.000+00:00',
                           'binding' => 'blackhole',
                           'routing_domain' => 'c1-t.msyscloud.com',
                           'raw_reason' => '551 5.7.0 [internal] recipient blackholed',
                           'error_code' => '551'
                         },
                         {
                           'pathway_group' => 'default',
                           'binding_group' => 'default',
                           'timestamp' => '2015-09-04T21:23:31.000+00:00',
                           'binding' => 'blackhole',
                           'routing_domain' => 'c1-t.msyscloud.com',
                           'pathway' => 'default',
                           'friendly_from' => 'smoke.tester+1441401809@c1-t.msyscloud.com',
                           'rcpt_to' => 'inbound@c1-t.msyscloud.com',
                           'recv_method' => 'esmtp',
                           'msg_size' => '1417',
                           'type' => 'injection',
                           'msg_from' => 'smoke.tester+1441401809@c1-t.msyscloud.com'
                         }
                       ]


{ msg_from => 'smoke.tester+1441401809@c1-t.msyscloud.com',
  rcpt_to => 'inbound@c1-t.msyscloud.com',
  binding => 'blackhole',
  events => {
    injection => 1,
    bounce => { error_code => '551' }
  }
}
=cut

sub check_events {
  my ($self, $events, $desc) = @_;
  # iterate over events, return true if matches are found for all specified event types
  EVENT:
  for my $e (@{ $events || [] }) {
    # skip this event if the type isn't one we're looking for
    next EVENT if not $desc->{events}{ $e->{type} };
    # skip this event if any of the other top-level keys doesn't match
    KEY:
    for my $key (keys %{ $desc || {} }) {
      next KEY if $key eq 'events';
      if ($desc->{ $key } =~ /^\d+$/) {
        # numeric comparison
        next EVENT if $desc->{ $key } != $e->{ $key };
      } else {
        # string comparison
        next EVENT if $desc->{ $key } ne $e->{ $key };
      }
    }
    # TODO: check event-type-specific options

    # this event satisfies the condition we were looking for, delete it
    delete $desc->{events}{ $e->{type} };
  }

  # if there are any keys left in events, we're not done yet
  return not scalar(keys(%{ $desc->{events} }));
}

if (not caller()) {
  require Msys::Smoke::Config;
  my $C = Msys::Smoke::Config::load_test_config();

=cut
https://ebates.msyscloud.com/api/v1/message-events?from=2015-09-23T00:00&to=2015-09-23T23:59&page=1&per_page=10000&timezone=america/los_angeles
=cut
  my $me = __PACKAGE__->new(config => $C);
  my $params = {
    from => "2015-09-23T00:00",
    to => "2015-09-23T23:59",
    page => 1,
    per_page => 10,
    timezone => "america/los_angeles",
    #friendly_froms => 'smoke.tester+1441401809@c1-t.msyscloud.com',
    #events => 'injection,delivery,bounce,delay,policy_rejection',
  };
  my $res = $me->get_entries($params);
  if (not $res) {
    printf STDERR "ERROR: %s\n", $me->last_error();
  } else {
    print Dumper $res;
  }
}

1;

