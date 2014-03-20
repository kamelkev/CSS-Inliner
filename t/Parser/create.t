use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More;
plan(tests => 2);

use_ok('CSS::Inliner::Parser');

my $simple = CSS::Inliner::Parser->new();

#test creation of empty selector
$simple->add_rule({ name => 'qualified', prelude => '.empty', block => {} });

#test creation of initialized selector
$simple->add_rule({ name => 'qualified', prelude => '.bar', block => { color => 'blue', 'font-size' => '16px'} });

my $ordered = $simple->write();

my $expected = <<END;
.empty {
}
.bar {
	color: blue;
	font-size: 16px;
}
END

ok($expected eq $ordered);
