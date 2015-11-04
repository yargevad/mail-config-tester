package Msys::Smoke::HTMLReport;
use strict;
use Data::Dumper;
use vars qw/
  $HEADER_FORMAT
  $ROW_FORMAT
  $FOOTER
/;

sub new {
  my $class = shift;
  my ($self, %args) = ({}, @_);
  bless $self, $class;
  if (not $args{title}) {
    die "title is required when creating a report!";
  }
  for my $key (keys %args) {
    $self->{$key} = $args{$key};
  }
  $self->{_parts} = [];
  push @{ $self->{_parts} }, sprintf($HEADER_FORMAT, $args{title});
  return $self;
}

sub add_row {
  # label: status
  # detail
  my ($self, %args) = @_;
  if (not $args{label}) {
    warn "label is required when adding a row!";
    return undef;
  } elsif (not $args{status}) {
    warn "status is required when adding a row!";
    return undef;
  } elsif (not $args{detail}) {
    warn "detail is required when adding a row!";
    return undef;
  }
  push @{ $self->{_parts} }, sprintf($ROW_FORMAT, $args{label}, $args{status}, $args{detail});
  return $self->{_parts}[-1];
}

sub add_footer {
  my ($self, %args) = @_;
  push @{ $self->{_parts} }, $FOOTER;
  return $self->{_parts}[-1];
}

sub finish { goto &add_footer }

sub build_html {
  my ($self, %args) = @_;
  my $html = $self->{_html} = join("\n", @{ $self->{_parts} });
  return $html;
}

sub write_to_file {
  my ($self, %args) = @_;
  if (not $args{filename}) {
    warn "filename is required when writing to a file!";
    return undef;
  }
  open my $fh, '>', $args{filename};
  if (not $fh) {
    warn sprintf("couldn't write to file [%s]: %s", $args{filename}, $!);
    return undef;
  }
  if (not $self->{_html}) {
    $self->build_html();
  }
  print $fh $self->{_html};
  close $fh;
  return $args{filename};
}

if (not caller()) {
  my $R = __PACKAGE__->new(
    title => 'This is a test report',
  );
  $R->add_row(
    label => 'Label',
    status => 'Status',
    detail => '<p>Detail detail detail detail detail detail detail detail</p>',
  );
  $R->add_row(
    label => 'Bacon',
    status => 'Ipsum',
    detail => <<'    BACON',
<p>Bacon ipsum dolor amet cupim beef ribs drumstick, capicola turducken rump t-bone pork chop. Venison pancetta spare ribs swine, pork belly jerky drumstick boudin bacon shoulder. Chicken picanha venison ribeye pancetta ham hock bresaola pork salami ball tip short ribs strip steak. Turkey chicken cupim cow ball tip doner boudin, meatloaf pork belly brisket tenderloin pork andouille shank. Ball tip andouille prosciutto pork chop ribeye.</p>

<p>Boudin meatloaf beef ribs, kielbasa shank jowl shoulder turkey hamburger leberkas pork belly ham strip steak swine. Fatback venison pancetta pork boudin spare ribs ham ball tip ground round meatloaf ham hock. Tri-tip spare ribs rump corned beef sirloin. Picanha pastrami swine short loin pork chop. Landjaeger ground round jowl biltong venison shoulder frankfurter brisket pancetta ribeye beef ribs tail.</p>
    BACON
  );
  $R->finish();
  $R->write_to_file(
    filename => './html-report.html',
  );
}

BEGIN {
$HEADER_FORMAT = <<'HTML';
<html>
<head>
<link rel="stylesheet" type="text/css" href="http://www.messagesystems.com/dmarc-validator/validator.css">
<script type="text/javascript" src="http://www.messagesystems.com/scripts/jquery.js" charset="utf-8"></script>
</head>
<body>
<body>
<div class="inner">
  <div id="content" class="content-column">

<div id="results-container">
  <div class="row active" id="row0">
    <!--div><p></p></div-->
    <div class="message" id="message0" style="height: 38px;"><p><strong>%s</strong></p></div>
  </div><!--.row-->
  <script type="text/javascript">
  $(document).ready(function(){                                                                          $('div.row').each(function(){
      var rowHeight = $(this).height();
      $(this).children('div').css('height',rowHeight);
    });
  });
  </script>
  <div id="results0" class="results">
<div id="testresults" class="datatable">
<!-- end header -->

HTML


$ROW_FORMAT = <<'HTML';
  <div class="result">
    <div class="fieldtitle" style="height: 39px;"><p>%s:</p></div>
    <div class="fielddata pass" style="height: 39px;"><p>%s</p></div>
  </div>
  <div class="explanation">
    <div class="left-triangle"></div>
    <div class="inner-explanation">
      %s
    </div>
    <div class="right-triangle"></div>
  </div><!--.explanation-->
HTML


$FOOTER = <<'HTML';
</div><!-- #testresults-->
<div style="clear:both"></div>

<script type="text/javascript">
$(document).ready(function(){
  $('div.result div').click(function(){
    $(this).parent('div.result').next('div.explanation').toggleClass('active').children('div').slideToggle();
    $(this).parent('div.result').toggleClass("active");
    $(this).parent('div.result').siblings('div.result.active').removeClass("active").next('div.explanation.active').removeClass('active').children('div').slideUp();
  });
});
</script>

</div><!-- #results-container-->

  </div><!-- #content-->
</div>
</body>
</html>

HTML

}

1;

