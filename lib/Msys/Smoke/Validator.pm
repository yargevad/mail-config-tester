package Msys::Smoke::Validator;
use strict;

use JSON;
use LWP::UserAgent;
use Data::Dumper;

use Msys::API::v1::Base;
our @ISA = qw/Msys::API::v1::Base/;


sub new {
  my $class = shift;
  my $v = $class->SUPER::new(
    api_base => 'https://validator.messagesystems.com/api',
    type => 'adhoc',
    @_,
  );
  return $v;
}

sub generate_address {
  my $self = shift;

  if ($self->{DEBUG}) { # DEBUG stub
    return $self->{_json}->decode(
      # random existing one from database, with results
      '{"address":"dis6n3xj5uhvyac@validator.messagesystems.com"}');
      # new one i generated
      #'{"address":"9a3dmu5wpqeot8k@validator.messagesystems.com"}');
  }

  my ($base, $res) = ($self->{api_base}, undef);
  { local $self->{api_base} = sprintf('%s/generateaddress', $base);
    $res = $self->get_entry();
  }
  if (not $res) {
    return (undef, $self->last_error());
  }
  return $res;
}

sub list_tests {
  my $self = shift;
  my %args = @_;

  if ($self->{DEBUG}) { # DEBUG stub
    print "list_tests args: ", Dumper(\%args);
    return $self->{_json}->decode(
      '{"tests":[{"id":"2284","testdate":"05\/16\/2014  11:58:52","subject":"Test Letter Woody Proxy #2"},{"id":"2283","testdate":"05\/16\/2014  11:55:54","subject":"Test Letter Swift Proxy #2"},{"id":"2282","testdate":"05\/16\/2014  11:54:59","subject":"Test Letter Swift Proxy"},{"id":"2281","testdate":"05\/16\/2014  11:52:55","subject":"Test Letter Swift Proxy"},{"id":"2280","testdate":"05\/16\/2014  11:51:50","subject":"Test Letter"},{"id":"2279","testdate":"05\/16\/2014  11:45:49","subject":"UITM. \u041f\u0440\u0438\u0433\u043b\u0430\u0448\u0430\u0435\u043c \u0441\u0442\u0430\u0442\u044c \u0443\u0447\u0430\u0441\u0442\u043d\u0438\u043a\u043e\u043c"}]}');
  }

  my $str = sprintf('email=%s', $args{email});
  my ($base, $res) = ($self->{api_base}, undef);
  { local $self->{api_base} = sprintf('%s/listtests', $base);
    $res = $self->post_entry({
      content => $str,
      content_type => 'application/x-www-form-urlencoded',
    });
  }

  return $res;
}

sub get_test_message {
  my $self = shift;
  my %args = @_;

  if ($self->{DEBUG}) { # DEBUG stub
  }

  my $str = sprintf('test=%d', $args{test});
  my ($base, $res) = ($self->{api_base}, undef);
  { local $self->{api_base} = sprintf('%s/gettestmessages', $base);
    $res = $self->post_entry({
      content_type => 'application/x-www-form-urlencoded',
      content => $str,
    });
  }

  return $res;
}

sub get_test_results {
  my $self = shift;
  my %args = @_;

  if ($self->{DEBUG}) { # DEBUG stub
    print "get_test_results args: ", Dumper(\%args);
    return $self->{_json}->decode(
      '{"results":{"test_id":2284,"date":"05\/16\/2014 11:58:52","subject":"Test Letter Woody Proxy #2","ip":"62.80.173.213","domain":"woody.pe.com.ua","from":null,"arec_match":"Yes","ptr_ehlo_match":"Yes","rec_hdrs_pass":"PASS","received_hdrs":"from [62.80.173.213] ([62.80.173.213:26333] helo=woody.pe.com.ua) by validator (envelope-from <i.kravchenko@pe.com.ua>) (ecelerity 3.5.5.39309 r(Platform:3.5.5.0)) with ESMTP id 26\/33-01682-B7DF5735; Fri, 16 May 2014 07:58:51 -0400from [10.1.1.61] (helo=i-kravchenko) by woody.pe.com.ua with smtp (Exim 4.82 (FreeBSD)) (envelope-from <i.kravchenko@pe.com.ua>) id 1WlGTg-0008Iu-83 for dis6n3xj5uhvyac@validator.messagesystems.com; Fri, 16 May 2014 14:39:04 +0300","clamav":"PASS","commtouch_class":"Unknown","commtouch_virus":"Unknown","spf_status":"PASS","blacklist_hit":"No","dkim":"PASS","dmarc":"PASS"}}');
  }

  my $str = sprintf('email=%s&test=%d', $args{email}, $args{test});
  my ($base, $res) = ($self->{api_base}, undef);
  { local $self->{api_base} = sprintf('%s/gettestresults', $base);
    $res = $self->post_entry({
      content_type => 'application/x-www-form-urlencoded',
      content => $str,
    });
  }

  if (defined($res)) {
    $res->{results}{test_id} = $args{test};
  }
  return $res;
}

sub wait_for_validator_results {
  my $self = shift;
  if (ref($self) ne __PACKAGE__) {
    printf STDERR "wait_for_validator_results needs first arg of type %s\n", __PACKAGE__;
    return undef;
  }
  my %args = @_;
  my $email = $args{email};
  if (not $email) {
    die "wait_for_validator_results: need an address to search for!";
  }
  my $pause = $args{pause} || 2; # seconds
  die "`pause` must be an integer" if $pause =~ /\D/;
  my $tries = $args{tries} || 15;
  die "`tries` must be an integer" if $tries =~ /\D/;

  my $i = 0;
  while (1) {
    my $list = $self->list_tests(
      email => $email,
    );
    if (not $list or not scalar(@{ $list->{tests} || [] })) {
      printf STDERR "waiting %ds for [%s]...\n", $pause, $email;
      sleep($pause);
      if (++$i >= $tries) {
        die sprintf("stopped waiting for [%s] after %ds.", $email, $pause * $tries);
      }
      next;
    }

    my $test = $self->{_test} = $list->{tests}[0];
    my $res = $self->get_test_results(
      email => $email,
      test => $test->{id},
    );
    if (not $res->{results}) {
      die sprintf("unexpected validator results: %s\n", Dumper($res->{results}));
    }

    my $msg = $self->get_test_message(test => $test->{id});
    if (defined($msg)) {
      $res->{results}{message} = $msg->{message};
    }

    return $res->{results};
  }
}

# test methods when module is called directly
if (not caller()) {
  require Msys::Smoke::Config;
  my $C = Msys::Smoke::Config::load_test_config();
  my $v = __PACKAGE__->new(
    config => $C,
    DEBUG => 1,
  );
  #my $messages = $v->get_test_message(test => 16491);
  #print "messages: ", Dumper($messages);
  #exit;

  #my $addr = $v->generate_address();
  #print "address: ", Dumper($addr);

  my $addr = { address =>  '1qvp2i48z0dkj6m@validator.messagesystems.com' };
  my $tests = $v->list_tests(email => $addr->{address});
  print "tests: ", Dumper($tests);
  $v->{DEBUG} = 0;

  my $results = $v->get_test_results(
    email => $addr->{address},
    #test => $tests->{tests}[0]{id},
    test => 2279,
  );
  print "results: ", Dumper($results);
}

1;

