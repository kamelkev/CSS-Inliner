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

sub parse_content {
  my $self = shift;

  if (!$self->{_implicit_tags}) {
    $self->SUPER::parse_content(@_);

    # Due to the perverse arguments given above we may end up with an oddly nested tree
    my @roots = $self->find_by_tag_name('tag', 'html');
    if (scalar @roots > 1) {
      my $real_root = $roots[scalar @roots - 1];

      $real_root->detach();

      foreach my $elem ($self->content_list()) {
        $elem->delete();
      }

      foreach my $attr ($real_root->all_attr_names()) {
        if ($attr !~ /^_/) {
          $self->attr($attr, $real_root->attr($attr));
        }
      }

      foreach my $elem ($real_root->content_list()) {
        if (ref $elem) {
          $self->insert_element($elem);
          $self->pos($self);
        }
      }

      $real_root->destroy();
    }
  }
  else {
    $self->SUPER::parse_content(@_);
  }

  return();
}

1;
