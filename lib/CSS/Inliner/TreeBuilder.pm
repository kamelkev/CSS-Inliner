package CSS::Inliner::TreeBuilder;
use strict;
use warnings;

use Storable qw(dclone);

BEGIN {
#  $HTML::TreeBuilder::DEBUG = 1;
}

use base qw(HTML::TreeBuilder);

=pod

=head1 NAME

CSS::Inliner::TreeBuilder - Parser that builds a HTML syntax tree

=head1 SYNOPSIS

 use CSS::Inliner::TreeBuilder;

 foreach my $file_name (@ARGV) {
   my $tree = CSS::Inliner::TreeBuilder->new();
   $tree->parse_file($file_name);

   print "Hey, here's a dump of the parse tree of $file_name:\n";
   $tree->dump(); # a method we inherit from HTML::Element
   print "And here it is, bizarrely rerendered as HTML:\n", $tree->as_HTML, "\n";

   $tree = $tree->delete();
 }

=head1 DESCRIPTION

Class to handling parsing of generic HTML

This sub-module is derived from HTML::TreeBuilder. The aforementioned module has some substantial
issues when the implicit_tags flag is set which require the parse method to be overridden.

=cut

sub relaxed {
  my $self = shift;
  my $value = shift;

  if (defined($value)) {
    $self->{_relaxed} = $value;
  }

  return $self->{_relaxed};
}

sub parse_content {
  my $self = shift;

  if ($self->relaxed()) {
    # protect declarations... parser is too strict here
    $_[0] =~ s/\<!([^>]+)\>/\<decl ~pi="1" \>$1<\/decl\>/g;

    $self->SUPER::parse_content(@_);

    $self->{_tag} = '~literal';
    $self->{text} = '';

    my @decls = $self->look_down('_tag','decl','~pi','1');
    foreach my $decl (@decls) {
      my $text = '<!' . $decl->as_text() . '>';
      my $literal = HTML::Element->new('~literal', 'text' => $text );

      $decl->replace_with($literal);
    }
  }
  else {
    $self->SUPER::parse_content(@_);
  }

  return();
}

1;
