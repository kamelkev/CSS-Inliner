use Test::More;
plan(tests => 10);

use_ok('CSS::Inliner');
#require_ok('./html/acidtest.html');

#need better way of opening this
open( my $fh, 't/html/acidtest.html' ) or die "can't open!\n";
my $html = do { local( $/ ) ; <$fh> } ;

my $inliner = CSS::Inliner->new();
$inliner->read({html => $html});
my $inlined = $inliner->inlinify();

warn $inlined;

#test isn't done yet.......
