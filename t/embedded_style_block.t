use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More;
use Cwd;
use CSS::Inliner;

use FindBin qw($Bin);

plan(tests => 1);

my $html_path = "$Bin/html/";
my $test_url = 'http://rawgithub.com/kamelkev/CSS-Inliner/master/t/html/embedded_style.html';
my $result_file = $html_path . 'embedded_style_result.html';

open( my $fh, $result_file ) or die "can't open $result_file: $!!\n";
my $correct_result = do { local( $/ ) ; <$fh> } ;

my $inliner = CSS::Inliner->new();
$inliner->fetch_file({url => $test_url});
my $inlined = $inliner->inlinify();

ok($inlined eq $correct_result, 'result was correct');
