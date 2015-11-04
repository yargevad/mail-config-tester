package Msys::Smoke::Inject;
use strict;

use lib './lib';
use Msys::Smoke::SMTPAPI;
# FIXME: allow configurable api version
use Msys::API::v1::Transmission;

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

# inject using the configured protocol (smtp, rest)

1;

