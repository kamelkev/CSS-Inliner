# $Id$
#
# Copyright 2009 MailerMailer, LLC
#
# Based loosely on the TamTam RubyForge project:
# http://tamtam.rubyforge.org/

package CSS::Inliner;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = sprintf "%d", q$Revision$ =~ /(\d+)/;

use Carp;

use HTML::TreeBuilder;
use CSS::Tiny;
use HTML::Query 'query';

=pod

=head1 NAME

CSS::Inliner - Library for converting CSS <style> blocks to inline styles.

=head1 SYNOPSIS

use Inliner;

my $inliner = new Inliner();

$inliner->read_file({filename => 'myfile.html'});

print $inliner->inlinify();

=head1 DESCRIPTION

Library for converting CSS style blocks into inline styles in an HTML
document.  Specifically this is intended for the ease of generating
HTML emails.  This is useful as even in 2009 Gmail and Hotmail don't
support top level <style> declarations.

Methods implemented are:

=cut

=pod

=head2 new()

Instantiates the Inliner object. Sets up class variables that are used
during file parsing/processing.

=cut

sub new {
  my $this = shift;
  my $class = ref($this) || $this;

  my $self = {
              css => undef,
              html => undef,
              html_tree => undef,
             };

  if (@_) {
    croak "Invalid number of arguments";
  }

  bless $self, $class;
  return $self;
}

=pod

=head2 read_file( params )

Opens and reads an HTML file that supposedly contains both HTML and a
style declaration.  It subsequently calls the read() method
automatically.

This method requires you to pass in a params hash that contains a
filename argument. For example:

$self->read_file({filename => 'myfile.html'});

=cut

sub read_file {
  my ($self,$params) = @_;

  unless ($params && $$params{filename}) {
    croak "You must pass in hash params that contain a filename argument";
  }

  open FILE, "<", $$params{filename} or die $!;
  my $html = do { local( $/ ) ; <FILE> } ;

  $self->read({html => $html});

  return();
}

=pod

=head2 read( params )

Reads html data and parses it.  The intermediate data is stored in
class variables.

The <style> block is ripped out of the html here, and stored
separately. Class/ID/Names used in the markup are left alone.

This method requires you to pass in a params hash that contains scalar
html data. For example:

$self->read({html => $html});

=cut

sub read {
  my ($self,$params) = @_;

  unless ($params && $$params{html}) {
    croak "You must pass in hash params that contains html data";
  }

  my $tree = new HTML::TreeBuilder();
  $tree->parse($$params{html});

  #rip all the style blocks out of html tree, and return that separately
  #the remaining html tree has no style block(s) now
  my $style = $self->_get_style({tree_content => $tree->content()});

  #stash the stylesheets
  $self->{css} = $style;

  #keep the html tree for later so we don't have to reparse
  $self->{html_tree} = $tree;

  return();
}

=pod

=head2 inlinify()

Processes the html data that was entered through either 'read' or
'read_file', returns a scalar that contains a composite chunk of html
that has inline styles instead of a top level <style> declaration.

Note that the class/id/names that are used within the markup are left
alone, but aren't no-ops as there is no <style> block in the resulting
html.

=cut

sub inlinify {
  my ($self,$params) = @_;

  unless ($self && ref $self) {
    croak "You must instantiate this class in order to properly use it";
  }

  unless ($self->{css} && $self->{html_tree}) {
    croak "You must instantiate and read in your content before inlinifying";
  }

  #parse and store the stylesheet as a hash object
  my $css = CSS::Tiny->read_string($self->{css});

  #we still have our tree, let's reuse it
  my $tree = $self->{html_tree};

  foreach my $key (keys %{$css}) {
    my $elements = $tree->query($key);

    #if an element matched a style within the document, convert it to inline
    foreach my $element (@{$elements}) {
      my $inline = $self->_expand({style => $$css{$key}});
      my $cur_style = $self->attr('style');
      $element->attr('style',$cur_style . $inline);
    }
  }

  return $tree->as_HTML();
}

##################################################################
#                                                                #
# The following are all class methods and are not for normal use #
#                                                                #
##################################################################

sub _get_style {
  my ($self,$params) = @_;

  my $style = '';

  foreach my $i (@{$$params{tree_content}}) {
    next unless ref $i eq 'HTML::Element';

    if (($i->tag eq 'style') && ($i->attr('media') =~ m/\b(all|screen)\b/)) {

      foreach my $item ($i->content_list()) {
          $style .= $item;
      }
      $i->delete();
     }

    # Recurse down tree
    if (defined $i->content) {
      $style .= $self->_get_style({tree_content => $i->content});
    }
  }

  return $style;
}

sub _expand {
  my ($self, $params) = @_;

  my $style = $$params{style};
  my $inline = '';
  foreach my $key (keys %{$style}) {
    $inline .= $key . ':' . $$style{$key} . ';';
  }

  return $inline;
}

1;

=pod

=head1 AUTHOR

Kevin Kamel <C<kamelkev@mailermailer.com>>

=head1 LICENSE

This module is Copyright 2009 Khera Communications, Inc.  It is
licensed under the same terms as Perl itself.

=cut
