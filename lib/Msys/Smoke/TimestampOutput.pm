package Msys::Smoke::TimestampOutput;
use strict;
use POSIX 'strftime';
$| = 1;

my $_counter = 0;

sub fork_and_prepend_timestamps {
  # only fork once kthx
  $_counter++;
  return if $_counter > 1;

  my (%args) = @_;
  $args{filehandle} ||= \*STDERR;
  my $pid = undef;
  return if $pid = open($args{filehandle}, '|-');
  die sprintf('fork failed: %s', $!) if not defined $pid;
  $| = 1;
  while (<STDIN>) {
    print strftime('%Y-%m-%d %H:%M:%S%z ', localtime()), $_;
  }
  exit;
}

fork_and_prepend_timestamps();

1;

