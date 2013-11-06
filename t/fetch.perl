use strict;
use warnings;
use lib qw( ./lib ../lib );

use Cwd;
use CSS::Inliner;

my $url = shift || 'http://www.cpan.org/index.html';

my $inliner = CSS::Inliner->new({ relaxed => 1 });
$inliner->fetch_file({url => $url});
my $inlined = $inliner->inlinify({ relaxed => 1 });

print $inlined;

warn "================ ERRORS ===============";
foreach my $warning (@{$inliner->content_warnings}) {
  warn $warning;
}

