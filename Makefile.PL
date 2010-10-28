# $Id$
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'CSS::Inliner',
    PMLIBDIRS => [ 'lib' ],
    PREREQ_PM => {
	'HTML::TreeBuilder' => 0,
        'CSS::Simple' => 2874,
        'HTML::Query' => 0.07,
        'LWP' => 0,
        'URI' => 0,
        'Test::More' => 0
    },
    dist => {
	PREOP => 'pod2text lib/CSS/Inliner.pm > README',
    },
    'test' => {
	TESTS => join(' ', map { glob } qw( t/*.t )),
    },
    VERSION_FROM => 'lib/CSS/Inliner.pm',
    AUTHOR => 'Kevin Kamel <kamelkev@mailermailer.com>',
    ABSTRACT => 'Library for converting CSS <style> blocks to inline styles',
    LICENSE => 'perl',
);
