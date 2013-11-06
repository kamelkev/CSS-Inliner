use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More;
use Cwd;
use CSS::Inliner;

use FindBin qw($Bin);

plan(tests => 2);

my $html_path = "$Bin/html/";
my $test_file = $html_path . 'acidtest.html';
my $result_file = $html_path . 'acidtest_result.html';

open( my $fh, $test_file ) or die "can't open $test_file: $!!\n";
my $html = do { local( $/ ) ; <$fh> } ;

open( my $fh2, $result_file ) or die "can't open $result_file: $!!\n";
my $correct_result = do { local( $/ ) ; <$fh2> } ;

my $inliner = CSS::Inliner->new();
$inliner->read({html => $html});
my $inlined = $inliner->inlinify();

ok($inlined eq $correct_result, 'result was correct');

my $inliner2 = CSS::Inliner->new({ relaxed => 1 });
$inliner2->read({html => $html});
my $inlined2 = $inliner->inlinify();

ok($inlined2 eq $correct_result, 'relaxed parse result was correct');
