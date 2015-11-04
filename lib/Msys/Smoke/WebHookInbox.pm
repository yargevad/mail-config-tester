package Msys::Smoke::WebHookInbox;
use strict;
use List::Util qw/sum/;

use Msys::API::v1::Base;
our @ISA = qw/Msys::API::v1::Base/;
use Msys::API::v1::WebHooks;

my $WH_NAME_MAX = 24;

sub new {
  my $class = shift;
  my %args = @_;
  my $in = $class->SUPER::new(
    api_base => 'http://api.webhookinbox.com',
    type => 'adhoc',
    %args,
  );
  $in->{_config} = $args{config};
  return $in;
}

sub create {
  my $self = shift;
  my ($base, $res) = ($self->{api_base}, undef);
  { local $self->{api_base} = sprintf('%s/create/', $base);
    $res = $self->post_entry();
  }
  if (not $res) {
    return (undef, $self->last_error());
  }
  $self->{_inbox} = $res;
  printf STDERR "created inbox at %s\n", $self->target_url();
  return $res;
}

sub target_url {
  my $self = shift;
  my $base = $self->{_inbox}{base_url};
  if (not $base) {
    warn "no `base_url` defined - call `create` first!";
    return undef;
  }
  if ($base =~ /\/$/) {
    $base .= 'in/';
  } else {
    $base .= '/in/';
  }
  return $base;
}

sub items {
  my $self = shift;
  my $res = undef;
  my $get = {
      order => 'created',
      (defined($self->{_last_cursor})
        ? (since => sprintf('id:%d', $self->{_last_cursor}))
        : ()),
  };
  { local $self->{api_base} = sprintf('%sitems', $self->{_inbox}{base_url});
    # NB: this will potentially long-poll...
    # save duration and adjust timeout accordingly?
    $res = $self->get_entries($get);
  }
  $self->{_last_cursor} = $res->{last_cursor};
  return $res;
}

sub events_with_rcpt_to { goto &events_for_transmission; }

sub fetch_batch {
  my ($self, $args) = @_;
  my $items = $self->items();
  if (exists($items->{items}) and ref($items->{items}) ne 'ARRAY') {
    printf STDERR "WARNING: unexpected return value for items: %s", Dumper($items);
    return undef;
  }
  my $rv = [];
  if (not exists($items->{items}) or not scalar(@{ $items->{items} })) {
    return $rv;
  }

  ITEM:
  for my $item (@{ $items->{items} }) {
    if (not exists($item->{body})) {
      printf STDERR "WARNING: unexpected inbox item structure: %s\n", $self->{_json}->encode($item);
      next ITEM;
    }
    if ($item->{body} eq '{"msys":{}}') {
      next ITEM; # test events are safe to ignore
    }
    # $item->{body} is yet another json string; decode it
    my $events = $self->{_json}->decode($item->{body});
    if (not $events or ref($events) ne 'ARRAY') {
      printf STDERR ("WARNING: unexpected event structure: %s\n", $self->{_json}->encode($item));
      next ITEM;
    }

    EVENT:
    for my $e (@$events) {
      if (not exists($e->{msys}) or ref($e->{msys}) ne 'HASH') {
        printf STDERR "WARNING: received malformed event: %s\n", $self->{_json}->encode($e);
        next EVENT;
      }
      $e = $e->{msys};
      my $etype = (keys(%$e))[0];
      if (not $etype) {
        next EVENT; # ignore empty events
      } elsif ($etype !~ $Msys::API::v1::WebHooks::EVENT_TYPES) {
        printf STDERR "WARNING: unhandled event type [%s]\n", $etype;
        next EVENT;
      }
      $e = $e->{ $etype };

      my $type = $e->{type};
      if (not Msys::API::v1::WebHooks->is_valid_event_type($type)) {
        printf STDERR "WARNING: invalid type [%s]: (%s) %s\n", $type, $etype, $self->{_json}->encode($e);
        next EVENT;
      }

      push @$rv, $e;
    }
  }

  return $rv;
}

sub events_for_transmission {
  my ($self, $args) = @_;
  # rcpt_to filtering (from internet to momentum)
  my $rcpt_to = $args->{rcpt_to};
  my $msg_from = $args->{msg_from};
  # tid filtering (from momentum to internet)
  my $tid = $args->{transmission_id};
  if (not ($tid or $rcpt_to)) {
    warn "events_for_transmission requires a `rcpt_to` or `transmission_id`";
    return undef;
  }

  my $pause = $args->{pause} || 20; # seconds
  die "`pause` must be an integer" if $pause =~ /\D/;
  my $tries = $args->{tries} || 6; # two minutes total, by default
  die "`tries` must be an integer" if $tries =~ /\D/;
  $args->{_start} = time;

  my $total_elapsed = $args->{total_elapsed} || 0; # seconds
  die "`total_elapsed` must be an integer" if $total_elapsed =~ /\D/;
  if ($total_elapsed) {
    printf STDERR "NOTICE: collecting events for ~%ds...\n", $total_elapsed;
  }

  my $total_batches = $args->{total_batches} || 0; # number of batches
  die "`total_batches` must be an integer" if $total_batches =~ /\D/;
  if ($total_batches) {
    printf STDERR "NOTICE: collecting %d batches of events...\n", $total_batches;
  }

  my $expected = $args->{expected};
  if ($expected) {
    if (ref($expected) ne 'HASH') {
      warn "events_for_transmission param `expected` needs a hashref";
      return undef;
    }
    for my $en (keys %$expected) {
      if (not Msys::API::v1::WebHooks->is_valid_event_type($en)) {
        warn sprintf("invalid event type [%s]", $en);
        return undef;
      }
    }
    printf STDERR "NOTICE: waiting for events (%s)...\n",
      join(', ', map(sprintf('%s:%d', $_, $expected->{$_}), keys %$expected));
    # TODO: warn about impossible expectations like:
    # { injection => 1,
    #   delivery  => 5000 }
  }

  if (not($total_elapsed or $total_batches or $expected)) {
    warn "must specify one of `total_elapsed`, `total_batches`, `expected`";
    return undef;
  }

  my ($i, $rv) = (0, {map((lc($_)=>[]), keys(%$expected))});
  my ($ignored, $batches) = (0, 0);
  my %counts = ();

  while (1) {
    my $wh_start = time;
    if ($self->{verbose}) {
      printf STDERR "NOTICE: waiting for webhook data...\n";
    }
    my $items = $self->items();
    my $wh_elap = time - $wh_start;
    if ($self->{verbose}) {
      printf STDERR "NOTICE: webhook data returned after %ds\n", $wh_elap;
    }

    if (exists($items->{items}) and ref($items->{items}) ne 'ARRAY') {
      die sprintf("unexpected return value for items: %s", Dumper($items));
    }
    if (not exists ($items->{items}) or not scalar(@{ $items->{items} })) {
      my $elap = time - $args->{_start};
      my $sleep = $pause;
      if ($total_elapsed and $total_elapsed < $elap + $pause) {
        $sleep = $total_elapsed - $elap;
      }
      if ($self->{verbose}) {
        printf STDERR "NOTICE: sleeping for %ds after empty result...\n", $sleep;
      }
      sleep($sleep);
      if (++$i >= $tries) {
        die sprintf("stopped waiting for events after %ds.", $elap)
          if not ($total_elapsed or $total_batches);
      }
      next;
    }
    $batches++;

    # load matching events into return structure
    for my $item (@{ $items->{items} }) {
      if (not exists($item->{body})) {
        warn sprintf("unexpected inbox item structure: %s", $self->{_json}->encode($item));
        next;
      }
      if ($item->{body} eq '{"msys":{}}') {
        next; # test events are safe to ignore
      }
      # $item->{body} is yet another json string; decode it
      my $events = $self->{_json}->decode($item->{body});
      if (not $events or ref($events) ne 'ARRAY') {
        warn sprintf("unexpected event structure: %s", $self->{_json}->encode($events));
        next;
      }

      for my $e (@$events) {
        if (not exists($e->{msys}) or ref($e->{msys}) ne 'HASH') {
          warn sprintf("received malformed event: %s", $self->{_json}->encode($e));
          next;
        }
        $e = $e->{msys};
        my $etype = (keys(%$e))[0];
        if (not $etype) {
          next; # ignore empty events
        } elsif ($etype !~ $Msys::API::v1::WebHooks::EVENT_TYPES) {
          warn sprintf("unhandled event type [%s]", $etype);
          next;
        }
        $e = $e->{ $etype };

        my $type = $e->{type};
        if (not Msys::API::v1::WebHooks->is_valid_event_type($type)) {
          warn sprintf("invalid type [%s]: (%s) %s", $type, $etype, $self->{_json}->encode($e));
          next;
        }
        if ($tid and $e->{transmission_id} != $tid) { $ignored++; next; }
        if ($msg_from and lc($e->{msg_from}) ne $msg_from) { $ignored++; next; }
        if ($rcpt_to) {
          if ($type eq 'out_of_band' and $e->{msg_from} eq $rcpt_to) {
            # we want these, do nothing
          } elsif ($e->{rcpt_to} !~ $rcpt_to) {
            $ignored++;
            next;
          }
        }

        push @{ $rv->{ lc($type) } }, $e;
        $counts{ lc($type) }++;
      }
    }

    my $done = 1;
    if ($total_batches) {
      # collect N batches worth of events
      if ($batches < $total_batches) {
        $done = 0;
      }

    } elsif ($total_elapsed) {
      # collect events for N seconds
      my $elap = time - $args->{_start};
      if ($elap < $total_elapsed) {
        $done = 0;
      }

    } else {
      # exit if we've seen all the events we were looking for
      for my $et (keys %{ $expected || {} }) {
        my ($expect, $seen) = ($expected->{ $et }, $counts{ lc($et) });
        printf STDERR "%s: expected %d, saw %d, ignored %d\n",
          lc($et), $expect, $seen, $ignored;
        if ($expect > $seen) {
          $done = 0;
          last;
        }
      }
    }

    if ($done) {
      my $elap = time - $args->{_start};
      my $collected = 0;
      $collected += $counts{ lc($_) } for keys(%counts);
      printf STDERR "collected %d events from %d batches over %ds for %s\n",
        $collected, $batches, $elap, ($tid || $rcpt_to);
      return $rv;
    } else {
      my $elap = time - $args->{_start};
      my $sleep = $pause;
      if ($total_elapsed and $total_elapsed < $elap + $pause) {
        $sleep = $total_elapsed - $elap;
      }
      if ($self->{verbose}) {
        printf STDERR "NOTICE: sleeping for %ds after parsing events...\n", $sleep;
      }
      sleep($sleep);
      if (++$i >= $tries) {
        die sprintf("stopped waiting for events after %ds.", $elap)
          if not ($total_elapsed or $total_batches);
      }
    }
  }
}

sub events_by_rcpt_to {
  my ($self, $events, $args) = @_;
  if (not ref($events) or ref($events) ne 'HASH') {
    die "events_by_rcpt_to takes events as a hash ref";
  } elsif (not ref($args) or ref($args) ne 'HASH') {
    die "events_by_rcpt_to takes args as a hash ref";
  } elsif (not $args->{rcpt_to}) {
    die "events_by_rcpt_to requires `rcpt_to`";
  } elsif ($args->{event_type} and not Msys::API::v1::WebHooks->is_valid_event_type($args->{event_type})) {
    warn sprintf("invalid event type [%s]", $args->{event_type});
    return undef;
  }
  my $rv = [];
  for my $etype (keys %$events) {
    for my $event (@{ $events->{ $etype } }) {
      my ($rcpt_to, $msg_from) = ($event->{rcpt_to}, $event->{msg_from});
      next if $rcpt_to !~ $args->{rcpt_to};
      next if $args->{msg_from} and lc($msg_from) ne $args->{msg_from};
      next if $args->{event_type} and $event->{type} ne $args->{event_type};
      push @$rv, $event;
    }
  }
  return $rv;
}

sub count_events_by_rcpt_to {
  my ($self, $events, $args) = @_;
  if (not $args->{event_type}) {
    die "count_events_by_rcpt_to requires an event_type";
  }
  my $e = $self->events_by_rcpt_to($events, $args);
  return scalar(@{ $e || [] });
}

sub summarize {
  my ($self, $events) = @_;
  my $ev = {};
  for my $etype (keys %$events) {
    for my $event (@{ $events->{ $etype } }) {
      my $rcpt_to = $event->{rcpt_to};
      $ev->{ $rcpt_to } ||= [];
      push @{ $ev->{ $rcpt_to } }, $etype;
    }
  }
  my $rv = join("\n", map(
      sprintf('%s: %s', $_, join(', ', @{ $ev->{$_} })),
      keys %$ev)) ."\n";
  return $rv;
}

sub remove {
  my $self = shift;
  my ($base, $res) = ($self->{api_base}, undef);
  { local $self->{api_base} = $self->{_inbox}{base_url};
    $res = $self->delete_entry();
  }
  delete $self->{_inbox};
  return $res;
}

sub _wh_name_trunc {
  my (@atoms) = @_;
  my @lengths = map(length($_), @atoms);
  my @longest = ();

  # truncate longest string(s) by 1 character until we're <= max
  while (sum(@lengths) + (scalar(@atoms) - 1) > $WH_NAME_MAX) {
    #printf "DEBUG: sum %d max %d (%s)\n",
    #  sum(@lengths) + (scalar(@atoms) - 1), $WH_NAME_MAX, join(' ', @atoms);
    # find longest element(s)
    for (my $i = 0; $i <= $#lengths; $i++) {
      if (not scalar(@longest) or $lengths[$i] > $lengths[ $longest[0] ]) {
        #printf "       set longest to %d\n", $i;
        @longest = ($i)
      } elsif (scalar(@longest) and $lengths[$i] == $lengths[ $longest[0] ]) {
        #printf "       add %d to longest (%s)\n", $i, join(' ', @longest);
        push @longest, $i;
      }
    }
    chop(@atoms[@longest]);
    $lengths[$_]-- for @longest;
    @longest = ();
  }
  return @atoms;
}

sub setup {
  my ($self, $args) = @_;
  $args->{config} ||= $self->{_config};
  if (not $args->{config}) {
    warn "setup requires a config object";
    return undef;
  } elsif (not $args->{config}{subdomain}) {
    warn "config object must provide subdomain";
    return undef;
  } elsif (not $args->{config}{type}) {
    warn "config object must provide customer type";
    return undef;
  } elsif (lc($args->{events}) eq 'all') {
    $args->{events} = Msys::API::v1::WebHooks::valid_event_types();
  } elsif (not $args->{events} or ref($args->{events} ne 'ARRAY')) {
    warn "setup requires an array of event types `events`";
    return undef;
  }
  my $W = $self->{_W} = Msys::API::v1::WebHooks->new(
    config => $args->{config},
    LWP_DEBUG => $args->{LWP_DEBUG},
  );
  # webhook name is limited to 24 characters
  my $wh_name = join(' ', _wh_name_trunc($ENV{USER}, $args->{config}->test_customer(), 'test'));
  my $WH = $self->{_WH} = $W->post_entry({
    name => $wh_name,
    target => $self->target_url(),
    events => $args->{events},
  });
  return $WH;
}

sub DESTROY {
  my $self = shift;
  if ($self->{_inbox} and not $self->{_immortal}) {
    printf STDERR "auto-destroying inbox at [%s]\n", $self->target_url();
    $self->remove();
  }
}


1;

