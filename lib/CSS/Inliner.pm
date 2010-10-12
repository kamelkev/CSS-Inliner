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
use CSS::Simple;
use HTML::Query 'query';
use LWP::UserAgent;
use URI;

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

=head1 CONSTRUCTOR

=over 4

=item new ([ OPTIONS ])

Instantiates the Inliner object. Sets up class variables that are used
during file parsing/processing. Possible options are:

B<html_tree> (optional). Pass in a custom instance of HTML::Treebuilder

B<strip_attrs> (optional). Remove all "id" and "class" attributes during inlining

=back
=cut

sub new {
  my ($proto, $params) = @_;

  my $class = ref($proto) || $proto;

  my $self = {
    stylesheet => undef,
    css => CSS::Simple->new(),
    html => undef,
    html_tree => $$params{html_tree} || HTML::TreeBuilder->new(),
    strip_attrs => defined($$params{strip_attrs}) ? 1 : 0,
  };

  bless $self, $class;
  return $self;
}

=head1 METHODS

=cut

=pod

=over 5

=item fetch_file( params )

Fetches a remote HTML file that supposedly contains both HTML and a
style declaration. It subsequently calls the read() method
automatically.

This method expands all relative urls, as well as fully expands the 
stylesheet reference within the document.

This method requires you to pass in a params hash that contains a
url argument for the requested document. For example:

$self->fetch_file({ url => 'http://www.example.com' });

=cut

sub fetch_file {
  my ($self,$params) = @_;

  unless ($params && $$params{url}) {
    croak "You must pass in hash params that contain a url argument";
  }

  #fetch a absolutized version of the html
  my $html = $self->_fetch_html({ url => $$params{url}});

  $self->read({html => $html});

  return();
}

=item read_file( params )

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

=item read( params )

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

=item inlinify()

Processes the html data that was entered through either 'read' or
'read_file', returns a scalar that contains a composite chunk of html
that has inline styles instead of a top level <style> declaration.

=back

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

    $self->_get_css()->read({css => $self->{stylesheet}});

    my %matched_elements;
    my $count = 0;

    foreach my $key ($self->_get_css()->get_selectors()) {

      #skip over psuedo selectors, they are not mappable the same
      next if $key =~ /\w:(?:active|focus|hover|link|visited|after|before|selection|target|first-line|first-letter)\b/io;

      #skip over @import or anything else that might start with @ - not inlineable
      next if $key =~ /^\@/io;

      my $elements = $self->_get_tree()->query($key);

      # CSS rules cascade based on the specificity and order
      my $specificity = $self->specificity({rule => $key});

      #if an element matched a style within the document store the rule, the specificity
      #and the actually CSS attributes so we can inline it later
      foreach my $element (@{$elements}) {
        $matched_elements{$element->address()} ||= [];
        my %match_info = (
          rule     => $key,
          element  => $element,
          specificity   => $specificity,
          position => $count,
          css      => $self->_get_css()->get_properties({selector => $key}),
          );
  
          push(@{$matched_elements{$element->address()}}, \%match_info);
          $count++;
        }
      }

      #process all elements
      foreach my $matches (values %matched_elements) {
        my $element = $matches->[0]->{element};
        # rules are sorted by specificity, and if there's a tie the position is used
        # we sort with the lightest items first so that heavier items can override later
        my @sorted_matches = sort { $a->{specificity} <=> $b->{specificity} || $a->{position} <=> $b->{position} } @$matches;

        my %new_style;
        foreach my $match (@sorted_matches) {
          %new_style = (%new_style, %{$match->{css}});
        }

        # styles already inlined have greater precedence
        if (defined($element->attr('style'))) {
          my %cur_style = $self->_split({style => $element->attr('style')});
          %new_style = (%new_style, %cur_style);
        }

        $element->attr('style', $self->_expand({properties => \%new_style}));
      }

      #at this point we have a document that contains the expanded inlined stylesheet
      #BUT we need to collapse the properties to remove duplicate overridden styles
      $self->_collapse_inline_styles({content => $self->_get_tree()->content() });

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

###########################################################################################################
# from CSS spec at http://www.w3.org/TR/CSS21/cascade.html#specificity
###########################################################################################################
# A selector's specificity is calculated as follows:
#
#     * count the number of ID attributes in the selector (= a)
#     * count the number of other attributes and pseudo-classes in the selector (= b)
#     * count the number of element names in the selector (= c)
#     * ignore pseudo-elements.
#
# Concatenating the three numbers a-b-c (in a number system with a large base) gives the specificity.
#
# Example(s):
#
# Some examples:
#
# *             {}  /* a=0 b=0 c=0 -> specificity =   0 */
# LI            {}  /* a=0 b=0 c=1 -> specificity =   1 */
# UL LI         {}  /* a=0 b=0 c=2 -> specificity =   2 */
# UL OL+LI      {}  /* a=0 b=0 c=3 -> specificity =   3 */
# H1 + *[REL=up]{}  /* a=0 b=1 c=1 -> specificity =  11 */
# UL OL LI.red  {}  /* a=0 b=1 c=3 -> specificity =  13 */
# LI.red.level  {}  /* a=0 b=2 c=1 -> specificity =  21 */
# #x34y         {}  /* a=1 b=0 c=0 -> specificity = 100 */
###########################################################################################################

=pod

=item specificity()

Calculate the specificity for any given passed selector, a critical factor in determining how best to apply the cascade

A selector's specificity is calculated as follows:

* count the number of ID attributes in the selector (= a)
* count the number of other attributes and pseudo-classes in the selector (= b)
* count the number of element names in the selector (= c)
* ignore pseudo-elements.

The specificity is based only on the form of the selector. In particular, a selector of the form "[id=p33]" is counted 
as an attribute selector (a=0, b=0, c=1, d=0), even if the id attribute is defined as an "ID" in the source document's DTD. 

See the following spec for additional details:
L<http://www.w3.org/TR/CSS21/cascade.html#specificity>

=back

=cut


#this method is a rip of the parser from HTML::Query, adjusted to count
sub specificity {
  my ($self,$params) = @_;

  my $selectivity = 0;
  my $comops = 0;
  my $query = $$params{rule};

  while (1) {
    my $pos = pos($query) || 0;
    my $relationship = '';
    my $leading_whitespace;

    # ignore any leading whitespace
    if ($query =~ / \G (\s+) /cgsx) {
      $leading_whitespace = defined($1) ? 1 : 0;
    }

    # grandchild selector is whitespace sensitive, requires leading whitespace
    if ($leading_whitespace && $comops && ($query =~ / \G (\*) \s+ /cgx)) {
      #have to eat this character so regex can continue
    }

    # get other relationship modifiers
    if ($query =~ / \G (>|\+) \s* /cgx) {
      #have to eat this character so regex can continue
    }

    # optional leading word is a tag name
    if ($query =~ / \G(?!\*(?:\s+|$|\[))([\w*]+) /cgx) {
      $selectivity += 1;
    }

    if (($leading_whitespace || $comops == 0) && ($query =~ / \G (\*) /cgx)) {
      #eat the universal selector here
    }

    # loop to properly calculate specificity for term
    while (1) {
      my $inner = pos($query);
      
      # that can be followed by (or the query can start with) a #id
      if ($query =~ / \G \# ([\w\-]+) /cgx) {
        $selectivity += 100;
      }

      # and/or a .class
      if ($query =~ / \G \. ([\w\-]+) /cgx) {
        $selectivity += 10;
      }

      # and/or none or more [ ] attribute specs
      if ($query =~ / \G \[ (.*?) \] /cgx) {
        $selectivity += 10;
      }
      
      last if (defined($inner) && ($inner == pos($query)));
    }

    # so we can check we've done something
    $comops++;
    
    last if ($pos == pos($query));
  }

  return $selectivity;
}

####################################################################
#                                                                  #
# The following are all private methods and are not for normal use #
# I am working to finalize the get/set methods to make them public #
#                                                                  #
####################################################################

sub _fetch_url {
  my ($self,$params) = @_;

  # Create a user agent object
  my $ua = LWP::UserAgent->new;
  $ua->agent("CSS::Inliner" . $ua->agent);
  $ua->protocols_allowed( ['http','https'] );

  # Create a request     
  my $uri = URI->new($$params{url});

  my $req = HTTP::Request->new('GET',$uri);

  # Pass request to the user agent and get a response back
  my $res = $ua->request($req);

  # if not successful
  if (!$res->is_success()) {
    die 'There was an error in fetching the document for '.$uri.' : '.$res->message;
  }

  # Is it a HTML document
  if ($res->content_type ne 'text/html' && $res->content_type ne 'text/css') {
    die 'The web site address you entered is not an HTML document.';
  }

  # remove the <HTML> tag pair as parser will add it again.
  my $content = $res->content || ''; 
  $content =~ s|</?html>||gi;

  # Expand all URLs to absolute ones
  my $baseref = $res->base;

  return ($content,$baseref);
}

sub _fetch_html {
  my ($self,$params) = @_;

  my ($content,$baseref) = $self->_fetch_url({ url => $$params{url} });

  # Build the HTML tree
  my $doc = HTML::TreeBuilder->new();
  $doc->parse($content);
  $doc->eof;

  # Change relative links to absolute links
  $self->_changelink_relative({ content => $doc->content, baseref => $baseref});

  $self->_expand_stylesheet({ tree_content => $doc->content });

  return $doc->as_HTML(q@^\n\r\t !\#\$%\(-;=?-~'@,' ',{});
}

sub _changelink_relative {
  my ($self,$params) = @_;

  my $base = $$params{baseref};
  
  foreach my $i (@{$$params{content}}) {
  
    next unless ref $i eq 'HTML::Element';
  
    if ($i->tag eq 'img' or $i->tag eq 'frame' or $i->tag eq 'input' or $i->tag eq 'script') {
  
      if ($i->attr('src') and $base) {
        # Construct a uri object for the attribute 'src' value
        my $uri = URI->new($i->attr('src'));
        $i->attr('src',$uri->abs($base));
      }                         # end 'src' attribute
    }
    elsif ($i->tag eq 'form' and $base) {
      # Construct a new uri for the 'action' attribute value
      my $uri = URI->new($i->attr('action'));
      $i->attr('action', $uri->abs($base));
    }
    elsif (($i->tag eq 'a' or $i->tag eq 'area' or $i->tag eq 'link') and $i->attr('href') and $i->attr('href') !~ /^\#/) {
      # Construct a new uri for the 'href' attribute value
      my $uri = URI->new($i->attr('href'));

      # Expand URLs to absolute ones if base uri is defined.
      my $newuri = $base ? $uri->abs($base) : $uri;

      $i->attr('href', $newuri->as_string());
    }
    elsif ($i->tag eq 'td' and $i->attr('background') and $base) {
      # adjust 'td' background
      my $uri = URI->new($i->attr('background'));
      $i->attr('background',$uri->abs($base));
    }                           # end tag choices

    # Recurse down tree
    if (defined $i->content) {
      $self->_changelink_relative({ content => $i->content, baseref => $base });
    }
  }
}

sub _expand_stylesheet {
  my ($self,$params) = @_;

  my $stylesheets = 0; #we only allow for one declaration right now...

  foreach my $i (@{$$params{tree_content}}) {
    next unless ref $i eq 'HTML::Element';

    if (($i->tag eq 'link') && (((defined $i->attr('rel')) && ($i->attr('rel') eq 'stylesheet')) || (((defined $i->attr('type')) && $i->attr('type') eq 'text/css')))) {
      $stylesheets++;
    }

    #process this node if the html media type is screen, all or undefined (which defaults to screen)
    if (($i->tag eq 'style') && (!$i->attr('media') || $i->attr('media') =~ m/\b(all|screen)\b/)) {
      $stylesheets++;
    }

    #stop doing work right now, we won't be able to process successfully
    if ($stylesheets > 1) {
      die 'CSS::Inliner can only process one set of styles within a document';
    }

    #now that we know we are ok to fetch...
    if (($i->tag eq 'link') && (((defined $i->attr('rel')) && ($i->attr('rel') eq 'stylesheet')) || (((defined $i->attr('type')) && $i->attr('type') eq 'text/css')))) {

      my ($content,$baseref) = $self->_fetch_url({ url => $i->attr('href') });

      #remove the trailing part of the baseref to create the point at which the relative urls below get attached
      $baseref =~ s/[^\/]*?$//;

      #absolutized the assetts within the stylesheet that are relative 
      $content =~ s/(url\()
                  ["']?
                  ((?:(?!https?:\/\/)(?!\))
                 [^"'])*)
                  ["']?
            (?=\))
           /$1\'$baseref$2\'/xsgi;

      my $stylesheet = HTML::Element->new('style');
      $stylesheet->push_content($content);

      $i->replace_with($stylesheet);
    }

    # Recurse down tree only if we found a head block
    if (($i->tag eq 'head') && (defined $i->content)) {
      $self->_expand_stylesheet({tree_content => $i->content});
    }
  }

  return();
}

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

    # Recurse down tree only if we found a head block
    if ((defined $i->content) && (defined $i->tag) && ($i->tag eq 'head')) {
      $stylesheet .= $self->_parse_stylesheet({tree_content => $i->content});
    }
  }

  return $stylesheet;
}

sub _collapse_inline_styles {
  my ($self,$params) = @_;

  my $content = $$params{content};

  foreach my $i (@{$content}) {

    next unless ref $i eq 'HTML::Element';

    if ($i->attr('style')) {
      my $styles = {}; # hold the property value pairs
      foreach my $pv_pair (split /;/,  $i->attr('style')) {
        my ($key,$value) = split /:/, $pv_pair, 2;
        $$styles{$key} = $value;
      }

      my $collapsed_style = '';
      foreach my $key (sort keys %{$styles}) { #sort for predictable output
        $collapsed_style .= $key . ': ' . $$styles{$key} . '; ';
      }

      $collapsed_style =~ s/\s*$//;
      $i->attr('style', $collapsed_style); 
    }

    #if we have specifically asked to remove the inlined attrs, remove them
    if ($self->_strip_attrs()) {
      $i->attr('id',undef);
      $i->attr('class',undef);
    }

    # Recurse down tree
    if (defined $i->content) {
      $self->_collapse_inline_styles({content => $i->content});
    }
  }
}

sub _get_tree {
  my ($self,$params) = @_;

  return $self->{html_tree};
}

sub _get_css {
  my ($self,$params) = @_;

  return $self->{css};
}

sub _strip_attrs {
  my ($self,$params) = @_;

  return $self->{strip_attrs};
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

sub _split {
  my ($self, $params) = @_;
  my $style = $params->{style};
  my %split;

  # Split into properties
  foreach ( grep { /\S/ } split /\;/, $style ) {
    unless ( /^\s*([\w._-]+)\s*:\s*(.*?)\s*$/ ) {
      croak "Invalid or unexpected property '$_' in style '$style'";
    }
    $split{lc $1} = $2;
  }
  return %split;
}

1;

=pod

=head1 Sponsor

This code has been developed under sponsorship of MailerMailer LLC, http://www.mailermailer.com/

=head1 AUTHOR

Kevin Kamel <C<kamelkev@mailermailer.com>>

=head1 CONTRIBUTORS

Vivek Khera <C<vivek@khera.org>>
Michael Peters <C<wonko@cpan.org>>

=head1 LICENSE

This module is Copyright 2010 Khera Communications, Inc.  It is
licensed under the same terms as Perl itself.

=cut
