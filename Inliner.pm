# $Id$
#
# Copyright 2009 MailerMailer, LLC - http://www.mailermailer.com
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
use Tie::IxHash;

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
  my ($proto, $params) = @_;

  my $class = ref($proto) || $proto;

  my $self = {
              stylesheet => undef,
              css => CSS::Tiny->new(),
              html => undef,
              html_tree => $$params{html_tree} || HTML::TreeBuilder->new(),
             };

  tie %{$self->{css}}, 'Tie::IxHash'; # configure tiny to preserve order of rules

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

  $self->_get_tree()->store_comments(1);
  $self->_get_tree()->parse($$params{html});

  #rip all the style blocks out of html tree, and return that separately
  #the remaining html tree has no style block(s) now
  my $stylesheet = $self->_parse_stylesheet({tree_content => $self->_get_tree()->content()});

  #save the data
  $self->_set_html({ html => $$params{html} });
  $self->_set_stylesheet({ stylesheet => $stylesheet});

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

  unless ($self->{html} && defined $self->_get_tree()) {
    croak "You must instantiate and read in your content before inlinifying";
  }

  my $html;
  if (defined $self->_get_css()) {
    #parse and store the stylesheet as a hash object
    $self->_get_css()->read_string($self->{stylesheet});

    foreach my $key (keys %{$self->_get_css()}) {

      #skip over psuedo selectors, they are not mappable the same
      next if $key =~ /\w:(?:active|focus|hover|link|visited|after|before|selection|target|first-line|first-letter)\b/io;

      #skip over @import or anything else that might start with @ - not inlineable
      next if $key =~ /^\@/io;

      my $elements = $self->_get_tree()->query($key);

      #if an element matched a style within the document, convert it to inline
      foreach my $element (@{$elements}) {
        my $inline = $self->_expand({properties => $self->_get_css()->{$key}});

        my $cur_style = '';
        if (defined($element->attr('style'))) {
          $cur_style = $element->attr('style');
        }

        $element->attr('style',$cur_style . $inline);
      }
    }

    #at this point we have a document that contains the expanded inlined stylesheet
    #BUT we need to collapse the properties to remove duplicate overridden styles


    # The entities list is the do-not-encode string from HTML::Entities
    # with the single quote added.

    # 3rd argument overrides the optional end tag, which for HTML::Element
    # is just p, li, dt, dd - tags we want terminated for our purposes

    $html = $self->_get_tree()->as_HTML(q@^\n\r\t !\#\$%\(-;=?-~'@,' ',{});
  }
  else {
    $html = $self->{html};
  }

  return $html;
}

####################################################################
#                                                                  #
# The following are all private methods and are not for normal use #
# I am working to finalize the get/set methods to make them public #
#                                                                  #
####################################################################

sub _parse_stylesheet {
  my ($self,$params) = @_;

  my $stylesheet = '';

  foreach my $i (@{$$params{tree_content}}) {
    next unless ref $i eq 'HTML::Element';

    #process this node if the html media type is screen, all or undefined (which defaults to screen)
    if (($i->tag eq 'style') && (!$i->attr('media') || $i->attr('media') =~ m/\b(all|screen)\b/)) {

      foreach my $item ($i->content_list()) {
          # remove HTML comment markers
          $item =~ s/<!--//mg;
          $item =~ s/-->//mg;

          $stylesheet .= $item;
      }
      $i->delete();
     }

    # Recurse down tree
    if (defined $i->content) {
      $stylesheet .= $self->_parse_stylesheet({tree_content => $i->content});
    }
  }

  return $stylesheet;
}

sub _get_tree {
  my ($self,$params) = @_;

  return $self->{html_tree};
}

sub _get_css {
  my ($self,$params) = @_;

  return $self->{css};
}

sub _set_html {
  my ($self,$params) = @_;

  $self->{html} = $$params{html};

  return $self->{html};
}

sub _set_stylesheet {
  my ($self,$params) = @_;

  $self->{stylesheet} = $$params{stylesheet};

  return $self->{stylesheet};
}

sub _expand {
  my ($self, $params) = @_;

  my $properties = $$params{properties};
  my $inline = '';
  foreach my $key (keys %{$properties}) {
    $inline .= $key . ':' . $$properties{$key} . ';';
  }

  return $inline;
}

1;

=pod

=head1 Sponsor

This code has been developed under sponsorship of MailerMailer LLC, http://www.mailermailer.com/

=head1 AUTHOR

Kevin Kamel <C<kamelkev@mailermailer.com>>

=head1 LICENSE

This module is Copyright 2009 Khera Communications, Inc.  It is
licensed under the same terms as Perl itself.

=cut
