use strict;
use warnings;
use lib qw( ./lib ../lib );

use Cwd;
use CSS::Inliner;

my $url = shift || 'http://www.cpan.org/index.html';

my $inliner = CSS::Inliner->new({filter => \&filter, unfilter => \&unfilter});
#my $inliner = CSS::Inliner->new();
$inliner->fetch_file({url => $url});
my $inlined = $inliner->inlinify();

warn "================ FINAL HTML ===============";

print $inlined;

warn "================ ERRORS ===============";
foreach my $warning (@{$inliner->content_warnings}) {
  warn $warning;
}

sub filter { 
  my ($params) = @_;

  return $$params{content};
};

sub unfilter { 
  my ($params) = @_;

  return $$params{content};
};
