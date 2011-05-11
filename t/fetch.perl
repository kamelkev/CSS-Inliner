use strict;
use warnings;
use lib qw( ./lib ../lib );

use Cwd;
use CSS::Inliner;

my $url = shift || 'http://www.cpan.org/index.html';

my $inliner = CSS::Inliner->new();
$inliner->fetch_file({url => $url});
my $inlined = $inliner->inlinify();

use Data::Dumper;
print Dumper($inliner->_content_warnings());
