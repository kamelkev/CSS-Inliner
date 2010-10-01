# $Id: Makefile.PL 2170 2009-10-08 12:00:00Z kamelkev $
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'CSS::Inliner',
    PMLIBDIRS => [ 'lib' ],
    PREREQ_PM => {
	'HTML::TreeBuilder' => 0,
        'CSS::Tiny' => 0,
        'HTML::Query' => 0.03,
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
