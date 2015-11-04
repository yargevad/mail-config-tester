package Msys::API::v1::Recipients;
use strict;
use JSON;
use Data::Dumper;

use lib './lib';
use Msys::API::v1::Base;
our @ISA = 'Msys::API::v1::Base';

sub new {
  my $class = shift;
  my %args = @_;
  return $class->SUPER::new(
    api_path => 'recipient-lists',
    @_,
  );
}

if (not caller()) {
  my $RECREATE = 0;
  require Msys::Smoke::Config;
  my $C = Msys::Smoke::Config::load_test_config();

  my $r = __PACKAGE__->new(
    config => $C,
    #LWP_DEBUG => 1,
    DEBUG => 1,
  );

  # NB: list names may not contain spaces
  # TODO: make list name a required constructor parameter
  my $list_name = 'minordomo-devel';

  # get lists in the system
  my ($list_meta, $last_version) = (undef, 0);
  my $ents = $r->get_entries();
  if (not $ents) {
    print STDERR $r->last_error();
    exit(1);
  }

  # get the latest version of the list we're looking for
  print "Found lists:\n";
  for my $l (@{ $ents->{results} }) {
    next if $l->{name} ne $list_name;
    my ($name, $version) = split(' ', $l->{id});
    printf "  - %s (version %d)\n", $name, $version;
    if ($version > $last_version) {
      $list_meta = $l;
      $last_version = $version;
    }
  }

  if ($RECREATE) {
    printf "Recreating list %s from scratch\n", $list_name;

    # delete the existing list
    my $del = $r->delete_entry(sprintf('%s %d', $list_name, $last_version));
    if (not $del) {
      print STDERR $r->last_error();
      exit(1);
    }
    printf "Removed existing list %s (version %d)\n", $list_name, $last_version;

    # create the new list
    my $list = {
      id => sprintf('%s %d', $list_name, 1),
      name => $list_name,
      recipients => [
        { address => { name => 'Dave Gray', email => 'dgray@messagesystems.com' } },
        { address => { name => 'Harlan Feinstein', email => 'harlan.feinstein@messagesystems.com' } },
        { address => { name => 'Tom Thibodeau', email => 'thomas.thibodeau@messagesystems.com' } },
      ],
      #description => '',
      #attributes => {},
    };
    my $post = $r->post_entry({json => $list});
    $list_meta->{id} = sprintf('%s %d', $list_name, 1);
    $last_version = 0;
  }

  # get full list contents
  my $list = $r->get_entry($list_meta->{id}, { show_recipients => 'true' });
  if (not $list) {
    print STDERR $r->last_error();
    exit(1);
  }
  $list = $list->{results};
  printf "List [%s] has recipients (%d):\n", $list_meta->{name}, scalar(@{ $list->{recipients} });
  printf("  - \"%s\" <%s>\n", $_->{address}{name}, $_->{address}{email}) for @{ $list->{recipients} };

  # add a recipient to the list
  my $rand = int(rand(100_000))+1; # 1 to 100k inclusive
  push @{ $list->{recipients} }, {
    address => {
        name => sprintf('Dave Gray %d', $rand),
        email => 'dgray@messagesystems.com',
    }
  };
  printf "Adding new recipient \"%s\" <%s>\n", sprintf('Dave Gray %d', $rand), 'dgray@messagesystems.com';

  # fixup api response so it won't error out while consuming what it returned
  for my $recip (@{ $list->{recipients} }) {
    #if (defined $recip->{return_path} and $recip->{return_path} eq '') {
    #  delete $recip->{return_path};
    #}
  }

  # save the changes (add then delete)
  # increment list sequence stored as part of id
  $list->{id} = sprintf('%s %d', $list_name, $last_version + 1);
  # create the new version
  my $post = $r->post_entry({ json => $list });
  if (not $post) {
    print STDERR $r->last_error();
    exit(1);
  }
  printf "Saved new version of list %s (%d)\n", $list_name, $last_version + 1;

  # delete the old version
  my $del = $r->delete_entry(sprintf('%s %d', $list_name, $last_version));
  if (not $del) {
    print STDERR $r->last_error();
    exit(1);
  }
  printf "Removed old version of list %s (%d)\n", $list_name, $last_version;

  # TODO: find list members with random numbers as part of their names and remove them

  # NB: there is no "update", so
  #     any list changes (additions, deletions) will require creating a new list
  #     and then removing the old one.
  # TODO: figure out how to keep track of the current list name
  #   ID will contain a hashed value plus a counter. (shasum gives 41 byte results)
  #   Retrieve list of recipient lists - list with highest counter is most recent

  # TODO? split lists out into multiple "buckets" on a consistent hashing ring
  # see for visualization: http://basho.com/why-riak-just-works/
}

1;

