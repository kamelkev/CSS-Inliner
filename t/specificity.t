use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More;
use Cwd;
use CSS::Inliner;

plan(tests => 15);

my %rules = (
    "li"                    => 1,
    "ul li"                 => 2,
    "ul ol li"              => 3,
    "li.red"                => 11,
    "ul ol li.red"          => 13,
    "td.foo p.bar em"       => 23,
    "td.foo"                => 11,
    "td.foo p"              => 12,
    "td.foo p.bar em.blah"  => 33,
    "td p em"               => 3,
    "td #blah"              => 102,
    "#blah td"              => 102,
    "#blah td.foo"          => 112,
    "#blah td.foo span"     => 113,
    "#blah td.foo span.bar" => 123,
);

foreach my $rule (keys %rules) {
  my $weight = CSS::Inliner->specificity({rule => $rule});

  is($weight, $rules{$rule}, "correct weight for \"$rule\"");
}
