package Msys::API::v1::Suppression;
use strict;

use JSON;
use HTTP::Request::Common qw/GET PUT DELETE/;

use lib './lib';
use Msys::API::v1::Base;
our @ISA = qw/Msys::API::v1::Base/;

sub new {
  my $class = shift;
  return $class->SUPER::new(
    api_path => 'suppression-list',
    @_,
  );
}

sub post_entry {
  warn "POST is unused with the Suppression API";
  return undef;
}

# TODO: bulk PUT

sub put_entry {
  my ($self, $email, $args) = @_;
  my $j = { non_transactional => JSON::true };
  if ($args->{transactional}) {
    delete $j->{non_transactional};
    $j->{transactional} = JSON::true;
  }
  if ($args->{description}) {
    $j->{description} = $args->{description};
  }
  $args->{json} = $j;
  return $self->SUPER::put_entry($email, $args);
}

if (not caller()) {
  use Data::Dumper;
  my $S = __PACKAGE__->new(
    customer => 'foo',
    #LWP_DEBUG => 1,
  );

  ## unsub email address
  #my $email = 'dave.gray@messagesystems.com';
  #my $entry = undef;
  #if ($entry = $S->get_entry($email)) {
  #  printf "found entry: %s", Dumper($entry);
  #  if (not $S->delete_entry($email)) {
  #    die sprintf("couldn't remove [%s]!", $email);
  #  } else {
  #    printf "removed from the list [%s]\n", $email;
  #  }
  #} else {
  #  printf "not suppressed: %s\n", $email;
  #}

  ## dump all entries to file:
  #my $entries = $S->get_entries();
  #my $json = './supp.json';
  #open my $fh, '>', $json
  #  or die sprintf("couldn't write [%s]: %s", $json, $!);
  #print $fh $S->{_json}->encode($entries);
  #close $fh;

  ## unsub all "Manually Added" addresses
  #my $entries = $S->get_entries();
  #use Time::HiRes 'time';
  #my ($n, $i) = (scalar(@{ $entries->{results} || [] }), 0);
  #my ($start, $per) = (time, 500);
  #printf "NOTICE: got %d records to process...\n", $n;
  #for my $entry (@{ $entries->{results} }) {
  #  if (not(++$i % $per)) {
  #    my $elap = time - $start;
  #    printf "NOTICE: processed %d/%d in %.02f\n", $i, $n, $elap/$per;
  #    $start = time;
  #  }
  #  if ($entry->{source} ne 'Manually Added') {
  #    printf "NOTICE: ignoring [%s] entry\n", $entry->{source};
  #    next;
  #  }
  #  my $email = $entry->{recipient};
  #  $S->delete_entry($email);
  #}
  #my $elap = time - $start;
  #printf "NOTICE: processed %d/%d in %.02f\n", $i, $n, $elap/($i % $per);
  #print "NOTICE: done.\n";

}

1;

