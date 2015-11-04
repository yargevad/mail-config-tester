package Msys::Smoke::DNS;
use strict;

use Net::DNS;
use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw/
  mx_get
  mx_get_ips
  is_ip_rdns_valid
  dns_query
/;


my $D = Net::DNS::Resolver->new();

sub mx_get {
  my $domain = shift;
  my $mx = $D->send($domain, 'MX');
  my @ans = $mx->answer();
  if (not scalar(@ans)) {
    my $dns_err = $D->errorstring();
    printf STDERR "ERROR: Can't find MX records for [%s]: %s\n", $domain, $dns_err;

    if ($dns_err =~ /\bSERVFAIL\b/) {
      # if we get here, we're reporting an error and returning
      my $dotcount = $domain =~ tr/\.//;
      if ($dotcount > 1) {
        (my $base = $domain) =~ s/^[^.]+?\.//;
        printf STDERR "NOTICE: checking NS records for [%s]\n", $base;
        # get nameserver(s) for base domain
        my $ns = $D->send($base, 'NS');
        my @ns = $ns->answer();
        my @ns_str = map($_->nsdname(), @ns);
        if (scalar(@ns) > 0) {
          printf STDERR "NOTICE: [%s] has %d NS entries [%s]\n", $base, scalar(@ns), join(', ', @ns_str);
          # create new resolver targeting nameservers found above
          my $d = Net::DNS::Resolver->new(
            nameservers => [@ns_str],
          );
          # look up NS records for provided domain using new resolver
          $ns = $d->send($domain, 'NS');
          @ns = $ns->authority();
          @ns_str = map($_->nsdname(), @ns);
          printf STDERR "NOTICE: [%s] has %d NS entries [%s]\n", $domain, scalar(@ns), join(', ', @ns_str);
        } else {
          printf STDERR "WARNING: no NS records for [%s]\n", $base;
        }

      } else {
        printf STDERR "WARNING: [%s] isn't a subdomain, not checking base domain dns\n", $domain;
      }
    }

    my @auth = $mx->authority();
    printf(STDERR "%s\n", $_->string()) for @auth;
    return ();
  }
  return @ans;
}

sub mx_get_ips {
  my $domain = shift;
  my @mxs = mx_get($domain);
  return undef if not scalar(@mxs);
  my @rv = ();
  for my $mx (@mxs) {
    my ($a, $err) = dns_query(host => $mx->exchange());
    if ($err) {
      printf STDERR $err;
      next;
    }
    push @rv, @$a;
  }
  return @rv;
}

sub dns_query {
  my (%args) = @_;
  my $name = $args{host} || $args{ip};
  my $type = $args{type} || 'A';
  if (not $name) {
    return (undef, "ERROR: must specify 'host' or 'ip'\n");
  }

  my $res = $D->query($name, $type);
  if (not $res) {
    return (undef, sprintf("ERROR: %s (%s) failed: %s\n", $name, $type, $D->errorstring()));
  }
  my @ans = $res->answer();
  if (not scalar(@ans)) {
    return (undef, sprintf("WARNING: 0 results for [%s] (%s)\n", $name, $type));
  }

  return (\@ans, undef);
}

sub is_ip_rdns_valid {
  my (%args) = @_;
  my $ip = $args{ip};

  my $ptr_host = join('.', reverse split(/\./, $ip)) .'.in-addr.arpa';
  my $a_ptr = $D->query($ptr_host, 'PTR');
  if (not $a_ptr) {
    printf STDERR "ERROR: querying [%s] failed: %s\n", $ptr_host, $D->errorstring();
    return (undef, sprintf("ERROR: querying [%s] failed: %s\n", $ptr_host, $D->errorstring()));
  }

  for my $ptr_rr ($a_ptr->answer()) {
    my $ptr = $ptr_rr->rdatastr();
    printf STDERR "NOTICE: found %s [%s] for [%s]\n", $ptr_rr->type(), $ptr, $ip;
    my $ptr_a = $D->query($ptr, 'A');
    if (not $ptr_a) {
      printf STDERR "ERROR: querying [%s] failed: %s\n", $ptr, $D->errorstring();
      return (undef, sprintf("ERROR: querying [%s] failed: %s\n", $ptr, $D->errorstring()));
    }

    for my $ptr_a_rr ($ptr_a->answer()) {
      my $ptr_ip = $ptr_a_rr->address();
      printf STDERR "NOTICE: found %s [%s] for [%s]\n", $ptr_a_rr->type(), $ptr_ip, $ptr;
      if ($ptr_ip ne $ip) {
        printf STDERR "WARNING: FCrDNS failure (%s != %s)\n", $ptr_ip, $ip;
        return 0;
      } else {
        printf STDERR "NOTICE: FCrDNS configured properly for %s\n", $ptr_ip;
        return 1;
      }
    }

  }

  # if we get here, there were no results from the PTR lookup
  return (undef, sprintf("ERROR: no results for PTR lookup on [%s]\n", $ip));
}

1;

