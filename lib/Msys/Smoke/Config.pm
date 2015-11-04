package Msys::Smoke::Config;
use strict;
use Exporter;
our @ISA = ('Exporter');
our @EXPORT_OK = qw/
  random_binding
  load_test_config
  binding_names
  ip_addresses
/;

# NB: need to memoize in this module, instead of using `Memoize`
# different include paths can stil trigger the "literal 1" case
our $_cache = {};

our %API_BASES = (
  elite => 'https://%s.msyscloud.com/api/v1/%s',
  sparkpost => 'https://api.sparkpost.com/api/v1/%s',
);


=cut
All relative paths are interpeted to begin in
the current user's home directory.
=cut
sub read_config {
  my ($file) = shift;
  if (!$file) {
    die "no config file!";
  }
  if ($file !~ m|^/|) {
    $file = sprintf('%s/%s', $ENV{HOME}, $file);
  }
  my $c = undef;
  if ($c = $_cache->{$file}) {
    return $c;
  }
  if (not -e $file) {
    return (undef, "no such file [$file]");
  }
  if (not -r $file) {
    die sprintf("config not readable! [%s]", $file);
  }
  eval { $c = require $file };
  if ($@) {
    die sprintf(" syntax error in config! [%s]", $file);
  }
  $_cache->{$file} = $c;
  # save the filename that was loaded
  $c->{_file} = $file;
  return $c;
}

sub load_test_config {
  my $file = shift;
  $file //= '.msys/smoke.rc';
  my ($c, $err) = read_config($file);
  if (not $c) {
    $file = '.sperc';
    ($c, $err) = read_config($file);
    die $err if not $c;
  }

  my $test_cust = $c->{_testing};
  if (not $test_cust) {
    die "FATAL: no '_testing' customer defined!";
  } elsif ($test_cust and not $c->{ $test_cust }) {
    die sprintf("FATAL: '_testing' customer [%s] not found in config [%s]!\n",
      $test_cust, $file);
    exit(1);
  }

  my $test_binding = $c->{_test_binding};
  my $test_domain = $c->{_test_domain};
  my $test_protocol = $c->{_test_protocol} || 'rest';

  # the only reason we keep a reference to '_top' is to tell
  # which customer we're testing, so get rid of everything else
  for my $key (keys %$c) {
    next if $key =~ /^_/;
    next if $key eq $test_cust;
    delete $c->{ $key };
  }
  # keep a reference to the top of the config
  $c->{ $test_cust }{_top} = $c;
  $c = $c->{ $test_cust };

  # default the customer type to SparkPost Elite
  $c->{type} //= 'elite';
  my $cust_type = $c->{type};
  if ($cust_type eq 'elite') {
    # default the *.msyscloud.com subdomain to the customer name
    $c->{subdomain} ||= $test_cust;
  }

  # default the protocol to REST
  $c->{protocol} //= 'rest'; #'smtp'
  my ($flag, $P) = (undef, protocols($c));
  my $np = scalar(@$P);
  if ($np > 1 and not $test_protocol) {
    die sprintf("FATAL: must specify protocol - %s has %d configured", $test_cust, $np);
  }

  for my $p (@$P) {
    if ($p !~ /^(?:rest|smtp)$/i) {
      die sprintf("FATAL: unsupported protocol [%s] for [%s]!", $p, $test_cust);
    }
    if (lc($test_protocol) eq lc($p)) {
      $flag = 1;
    }
  }
  if (not $flag) {
    die sprintf("FATAL: configured protocol [%s] is not available for [%s]!", $test_protocol, $test_cust);
  }

  if ($cust_type ne 'sparkpost' and $test_binding) {
    if (not $c->{bindings}{ $test_binding }) {
      die sprintf("FATAL: invalid '_test_binding' (%s) for [%s]",
        $test_binding, $test_cust);
    }
    $c->{bindings} = { $test_binding => $c->{bindings}{ $test_binding } };
  }

  # make sure we get this from the right place;
  # we've already chroot'd into the client-specific config structure
  if ($cust_type ne 'sparkpost' and $test_domain) {
    my $b = $c->{bindings}{ $test_binding };
    if ($b->{domains}) {
      if (ref($b->{domains}) ne 'ARRAY') {
        die sprintf("FATAL: bindings.binding.domains must be an array for [%s] in [%s]!",
          $test_binding, $test_cust);
      }
      my $found = 0;
      for my $d (@{ $b->{domains} }) {
        if ($d eq $test_domain) {
          $found = 1;
        }
      }
      if (not $found) {
        die sprintf("FATAL: invalid '_test_domain' (%s) for [%s:%s]",
          $test_domain, $test_cust, $test_binding);
      }
      $c->{bindings}{ $test_binding }{domains} = [ $test_domain ];
    } elsif ($b->{domain} and $b->{domain} ne $test_domain) {
      die sprintf("FATAL: invalid '_test_domain' (%s) for [%s:%s]",
        $test_domain, $test_cust, $test_binding);
    }
  }
  bless $c, __PACKAGE__;
  if ($cust_type ne 'sparkpost') {
    printf "NOTICE: testing %s customer %s (%s) > binding (%s) > domain %s\n",
      $cust_type, $test_cust, $test_protocol, $test_binding || 'all', $test_domain || '(all)';
  } else {
    printf "NOTICE: testing with sparkpost customer %s (%s)\n", $test_cust, $test_protocol;
  }

  return $c;
}

sub test_customer {
  my $c = shift;
  return $c->{_top}{_testing};
}

sub random_binding {
  my $cfg = shift;
  if ($cfg->{type} eq 'sparkpost') {
    return 'sparkpost';
  }

  if (not exists $cfg->{bindings}) {
    die sprintf("FATAL: no bindings for %s:%s!", $cfg->{_top}{_file}, $cfg->{subdomain});
  } elsif (ref($cfg->{bindings}) ne 'HASH') {
    die sprintf("FATAL: bindings must be defined as a hash in %s!", $cfg->{_top}{_file});
  }
  my @bind_names = keys(%{ $cfg->{bindings} });
  if (not scalar(@bind_names)) {
    die sprintf("FATAL: no bindings defined in %s!", $cfg->{_top}{_file});
  }
  my $bind_idx = int(rand(scalar(@bind_names)));
  return $bind_names[$bind_idx];
}

sub binding_names {
  my $cfg = shift;
  return keys(%{ $cfg->{bindings} });
}

sub api_base {
  my ($cfg, $path) = @_;
  if (not $path) {
    my $msg = "'path' is a required parameter of api_base";
    warn $msg;
    return (undef, $msg);
  }
  if ($cfg->{type} eq 'sparkpost') {
    return sprintf($API_BASES{sparkpost}, $path);
  } elsif ($cfg->{type} eq 'elite') {
    return sprintf($API_BASES{elite}, $cfg->{subdomain}, $path);
  } elsif ($cfg->{type} eq 'onprem') {
    return sprintf('%s/%s', $cfg->{api_base}, $path);
  }
}

sub fbl_domains {
  my $cfg = shift;
  if ($cfg->{base_domain}) {
    return [ "$cfg->{base_domain}" ];
  }
  my $rv = [];
  my @b = $cfg->binding_names();
  for my $bn (@b) {
    push @$rv, @{ $cfg->binding_domains($bn) };
  }
  return $rv;
}

sub binding_domains {
  my ($cfg, $name) = @_;
  if ($cfg->{type} eq 'sparkpost') {
    return ['feinsteins.net']; # FIXME: hardcoded
  }

  my $bc = $cfg->{bindings}{ $name };
  my $domain = $bc->{domain};
  my $domains = $bc->{domains};
  if (not ref($domains)) {
    if ($domains) {
      $domains = [ $domains ];
    } elsif ($domain) {
      $domains = [ $domain ];
    }
  } elsif (ref($domains) ne 'ARRAY') {
    die sprintf("FATAL: bindings.binding.domains must be an array for [%s] in [%s]!",
      $name, $cfg->{_top}{_file});
  }
  return $domains;
}

sub protocols {
  my $cfg = shift;
  my $p = $cfg->{protocol};
  my $ps = $cfg->{protocols};
  if (not ref($ps)) {
    if ($ps) {
      $ps = [ $ps ];
    } elsif ($p) {
      $ps = [ $p ];
    }
  } elsif (ref($ps) ne 'ARRAY') {
    die sprintf("FATAL: protocols must be an array in [%s]!", $cfg->{_top}{_file});
  }

  return $ps;
}

sub ip_addresses {
  my ($cfg, $name) = @_;
  my $bc = $cfg->{bindings}{ $name };
  my $ip = $bc->{ip};
  my $ips = $bc->{ips};
  if (not ref($ips)) {
    if ($ips) {
      $ips = [ $ips ];
    } elsif ($ip) {
      $ips = [ $ip ];
    }
  } elsif (ref($ips) ne 'ARRAY') {
    die sprintf("FATAL: bindings.binding.ips must be an array for [%s] in [%s]!",
      $name, $cfg->{_top}{_file});
  }
  return $ips;
}

sub custom_headers {
  my ($cfg, $name) = @_;
  my $bc = $cfg->{bindings}{ $name };
  if (ref($bc->{headers}) eq 'HASH' and scalar(keys(%{ $bc->{headers} }))) {
    return $bc->{headers};
  }
  return {};
}


1;

