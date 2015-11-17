use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More;
use Cwd;
use CSS::Inliner;

use FindBin qw($Bin);
use charnames ":full";
use Encode;

plan(tests => 1);

my $html_path = "$Bin/html/";
my $test_file = $html_path . 'acidtest_utf8.html';
my $result_file = $html_path . 'acidtest_result.html';

open( my $fh, $test_file ) or die "can't open $test_file: $!!\n";
my $raw_html = do { local( $/ ) ; <$fh> } ;
my $html = ($raw_html =~ s/\\N\{(U\+[0-9A-F]+|[\w\s]+)\}/charnames::string_vianame("$1")/ogser);

#die $1;

warn encode('utf-8', $html);

open( my $fh2, $result_file ) or die "can't open $result_file: $!!\n";
my $correct_result = do { local( $/ ) ; <$fh2> } ;

my $inliner = CSS::Inliner->new();

$inliner->read({ html => $html });
my $inlined = $inliner->inlinify();

ok($inlined eq $correct_result, 'result was correct');
