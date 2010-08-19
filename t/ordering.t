use Test::More;
plan(tests => 1);

use_ok('CSS::Inliner');

my $html = <<END;
<html>
 <head>
  <title>Test Document</title>
  <style type="text/css">
   .foo { color: red }
   .bar { color: blue; font-weight: bold; }
   .biz { color: green; font-size: 10px; }
  </style>
  <body>
    <h1 class="foo bar biz">Howdy!</h1>
    <h1 class="foo biz bar">Ahoy!</h1>
    <h1 class="bar biz foo">Hello!</h1>
    <h1 class="bar foo biz">Hola!</h1>
    <h1 class="biz foo bar">Gudentag!</h1>
    <h1 class="biz bar foo">Dziendobre!</h1>
  </body>
</html>
END

my $inliner = CSS::Inliner->new();
$inliner->read({html => $html});
$inliner->_get_css();


#attempt to shuffle up the rules
while (( $key, $value ) = each %{$inliner->_get_css()} ) {
    warn "$key is colored $value.\n";
}

#inline the document using the supposed shuffled rules
my $inlined = $inliner->inlinify();

warn $inlined;


ok($inlined =~ m/<h1 style="color:red;color:blue; font-weight: bold;">Howdy!<\/h1>/, 'h1 rule inlined');
