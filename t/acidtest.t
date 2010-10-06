use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More;
use Cwd;
use CSS::Inliner;

plan(tests => 1);

my $html_path = (getcwd =~ m/t/) ? getcwd . '/html/' : getcwd . '/t/html/';
my $test_file = $html_path . 'acidtest.html';
my $result_file = $html_path . 'acidtest_result.html';

open( my $fh, $test_file ) or die "can't open!\n";
my $html = do { local( $/ ) ; <$fh> } ;

open( my $fh2, $result_file ) or die "can't open!\n";
my $correct_result = do { local( $/ ) ; <$fh2> } ;

my $inliner = CSS::Inliner->new();
$inliner->read({html => $html});
my $inlined = $inliner->inlinify();

ok($inlined eq $correct_result, 'result was correct');
