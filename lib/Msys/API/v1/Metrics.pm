package Msys::API::v1::Metrics;
use strict;

use JSON;
use HTTP::Request::Common 'GET';

use Msys::API::v1::Base;
our @ISA = qw/Msys::API::v1::Base/;

sub new {
  my $class = shift;
  return $class->SUPER::new(
    api_path => 'metrics',
    @_,
  );
}

sub delete_entry {
  warn "DELETE is unused with the Metrics API";
  return undef;
}

sub put_entry {
  warn "PUT is unused with the Metrics API";
  return undef;
}

sub post_entry {
  warn "POST is unused with the Metrics API";
  return undef;
}

sub get_campaigns {
  my $self = shift;
  my $base = $self->{api_base};
  local $self->{api_base} = sprintf('%s/campaigns', $base);
  my $c = $self->get_entries();
  return $c->{results}{campaigns};
}

sub stats_by_campaign {
  my $self = shift;
  my $params = shift;
  my $base = $self->{api_base};
  local $self->{api_base} =  sprintf('%s/deliverability/campaign', $base);
  my $c = $self->get_entries($params);
  return $c->{results};
}

sub get_binding_groups {
  my $self = shift;
  my $base = $self->{api_base};
  local $self->{api_base} = sprintf('%s/binding-groups', $base);
  my $c = $self->get_entries();
  return $c->{results}{'binding-groups'};
}

sub stats_by_binding_group {
  my $self = shift;
  my $params = shift;
  my $base = $self->{api_base};
  local $self->{api_base} = sprintf('%s/deliverability/binding-group', $base);
  my $c = $self->get_entries($params);
  return $c->{results};
}

if (not caller()) {
  use Data::Dumper;
  use POSIX 'strftime';
  use Msys::Smoke::Config 'load_test_config';
  my $C = load_test_config();
  my $TYPE = 'binding_groups';

  my $S = __PACKAGE__->new(
    config => $C,
    LWP_DEBUG => 1,
  );

  if ($TYPE eq 'endpoints') {
    my $entries = $S->get_entries();
    print "$_\n" for @$entries;

  } elsif ($TYPE eq 'campaigns') {
    my $c = $S->get_campaigns();
    my $stats = $S->stats_by_campaign({
        metrics => join(',', qw/
          count_injected
          count_accepted
          count_rendered
          count_clicked
        /),
      campaigns => join(',', @$c),
      to => strftime('%Y-%m-%dT%H:%M', localtime(time)),
      from => strftime('%Y-%m-%dT%H:%M', localtime(time - 60*60*24)),
    });
    for my $row (@$stats) {
      printf "Campaign %s\ninj: %d\tacc: %d\topen: %d\tcl: %d\n", map($row->{$_}, qw/
        campaign_id
        count_injected
        count_accepted
        count_rendered
        count_clicked
      /);
    }

  } elsif ($TYPE eq 'binding_groups') {
    my $bg = $S->get_binding_groups();
    my $stats = $S->stats_by_binding_group({
        metrics => join(',', qw/
          count_injected
          count_accepted
          count_rendered
          count_unique_rendered
          count_clicked
          count_unique_clicked
        /),
      binding_groups => join(',', @$bg),
      to => strftime('%Y-%m-%dT%H:%M', localtime(time)),
      from => strftime('%Y-%m-%dT%H:%M', localtime(time - 60*60*24 * 7)),
    });
    for my $row (@$stats) {
      printf "Binding Group %s\ninj: %d\tacc: %d\topen: %d\tuopen: %d\tcl: %d\tucl: %d\n", map($row->{$_}, qw/
        binding_group
        count_injected
        count_accepted
        count_rendered
        count_unique_rendered
        count_clicked
        count_unique_clicked
      /);
    }
  }

}

1;

