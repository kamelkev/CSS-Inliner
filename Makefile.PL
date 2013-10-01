use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'CSS::Inliner',
    PMLIBDIRS => [ 'lib' ],
    PREREQ_PM => {
	'HTML::TreeBuilder' => 4.2,
        'HTML::Query' => 0.08,
        'LWP' => 0,
        'URI' => 0,
        'Test::More' => 0
    },
    'test' => {
	TESTS => join(' ', map { glob } qw( t/*.t )),
    },
    VERSION_FROM => 'lib/CSS/Inliner.pm',
    AUTHOR => 'Kevin Kamel <kamelkev@mailermailer.com>',
    ABSTRACT => 'Library for converting CSS <style> blocks to inline styles',
    LICENSE => 'perl',
);

sub MY::postamble {
  return <<'MAKE_FRAG';
all :: README

README: lib/CSS/Inliner.pm
	pod2text $> > README
MAKE_FRAG
}
