use Test::More;
plan(tests => 1);

use_ok('CSS::Inliner');

my $html = <<END;
<html>
 <head>
  <title>Test Document</title>
  <style type="text/css">
   .bar { color: blue }
   .foo { color: red }
  </style>
  <body>
    <h1 class="foo bar">Howdy!</h1>
  </body>
</html>
END

my $inliner = CSS::Inliner->new();
$inliner->read({html => $html});
my $inlined = $inliner->inlinify();

ok($inlined =~ m/<h1 style="color:red;color:blue">Howdy!<\/h1>/, 'h1 rule inlined');
