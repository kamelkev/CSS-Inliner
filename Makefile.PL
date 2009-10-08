# $Id: Makefile.PL 2170 2009-10-08 12:00:00Z kamelkev $
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME => 'CSS::Inliner',
    PREREQ_PM => {
	'LWP' => 0,
    },
    dist => {
	PREOP => 'pod2text Inliner.pm > README; perl mkcabundle > ca-bundle.crt',
    },
    VERSION_FROM => 'CSS-Inliner.pm',
    AUTHOR => 'Kevin Kamel <kamelkev@mailermailer.com>',
    ABSTRACT => 'Library for converting <style> blocks to inline styles',
    LICENSE => 'perl',
);
