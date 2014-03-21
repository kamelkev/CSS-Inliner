package CSS::Inliner;
use strict;
use warnings;

our $VERSION = '3941';

use Carp;

use Encode;
use LWP::UserAgent;
use URI;

use HTML::Query 'query';

use CSS::Inliner::TreeBuilder;
use CSS::Inliner::Parser;

=pod

=head1 NAME

CSS::Inliner - Library for converting CSS <style> blocks to inline styles.

=head1 SYNOPSIS

use Inliner;

my $inliner = new Inliner();

$inliner->read_file({ filename => 'myfile.html' });

print $inliner->inlinify();

=head1 DESCRIPTION

Library for converting CSS style blocks into inline styles in an HTML
document.  Specifically this is intended for the ease of generating
HTML emails.  This is useful as even in 2013 Gmail and Hotmail don't
support top level <style> declarations.

=cut

BEGIN {
  my $members = ['stylesheet','css','html','html_tree','query','strip_attrs','relaxed','leave_style','warns_as_errors','content_warnings'];

  #generate all the getter/setter we need
  foreach my $member (@{$members}) {
    no strict 'refs';

    *{'_' . $member} = sub {
      my ($self,$value) = @_;

      $self->_check_object();

      $self->{$member} = $value if defined($value);

      return $self->{$member};
    }
  }
}

=pod

=head1 METHODS

=over

=item E<32>new

Instantiates the Inliner object. Sets up class variables that are used
during file parsing/processing. Possible options are:

html_tree - (optional) Pass in a fresh unparsed instance of HTML::Treebuilder

NOTE: Any passed references to HTML::TreeBuilder will be substantially altered by passing it in here...

strip_attrs - (optional) Remove all "id" and "class" attributes during inlining

leave_style - (optional) Leave style/link tags alone within <head> during inlining

relaxed - (optional) Relaxed HTML parsing which will attempt to interpret non-HTML4 documents.

NOTE: This argument is not compatible with passing an html_tree.

=cut

sub new {
  my ($proto, $params) = @_;

  my $class = ref($proto) || $proto;

  # passed in html_tree argument must be of correct type
  # TODO: make sure tree has no content already
  if (defined $$params{html_tree} && $$params{html_tree} && ref $$params{html_tree} ne 'HTML::TreeBuilder') {
    croak 'Incompatible argument passed to new: "html_tree"';
  }

  # check to make sure caller is not trying to pass both an html_tree and setting relaxed flag
  # relaxed flag requires our own internal TreeBuilder, not HTML::TreeBuilder
  if (defined $$params{html_tree} && $$params{html_tree} && defined $$params{relaxed} && $$params{relaxed}) {
    croak 'Incompatible argument passed to new: "html_tree"';
  }

  my $self = {
    stylesheet => undef,
    css => CSS::Inliner::Parser->new({ warns_as_errors => $$params{warns_as_errors} }),
    html => undef,
    html_tree => defined($$params{html_tree}) ? $$params{html_tree} : CSS::Inliner::TreeBuilder->new(),
    query => undef,
    content_warnings => {},
    strip_attrs => (defined($$params{strip_attrs}) && $$params{strip_attrs}) ? 1 : 0,
    relaxed => (defined($$params{relaxed}) && $$params{relaxed}) ? 1 : 0,
    leave_style => (defined($$params{leave_style}) && $$params{leave_style}) ? 1 : 0,
    warns_as_errors => (defined($$params{warns_as_errors}) && $$params{warns_as_errors}) ? 1 : 0,
  };

  bless $self, $class;

  # configure tree
  $self->_html_tree->store_comments(1);
  if ($self->_relaxed()) {
    $self->_html_tree->ignore_unknown(0);
    $self->_html_tree->implicit_tags(0);
  }

  return $self;
}

=pod

=item fetch_file

Fetches a remote HTML file that supposedly contains both HTML and a
style declaration, properly tags the data with the proper characterset
as provided by the remote webserver (if any). Subsequently calls the
read method automatically.

This method expands all relative urls, as well as fully expands the
stylesheet reference within the document.

This method requires you to pass in a params hash that contains a
url argument for the requested document. For example:

$self->fetch_file({ url => 'http://www.example.com' });

=cut

sub fetch_file {
  my ($self,$params) = @_;

  $self->_check_object();

  unless ($params && $$params{url}) {
    croak 'You must pass in hash params that contain a url argument';
  }

  #fetch a absolutized version of the html
  my $html = $self->_fetch_html({ url => $$params{url} });

  $self->read({ html => $html });

  return();
}

=item read_file

Opens and reads an HTML file that supposedly contains both HTML and a
style declaration.  It subsequently calls the read() method
automatically.

This method requires you to pass in a params hash that contains a
filename argument. For example:

$self->read_file({ filename => 'myfile.html' });

Additionally you can specify the character encoding within the file, for
example:

$self->read_file({ filename => 'myfile.html', charset => 'utf8' });

=cut

sub read_file {
  my ($self,$params) = @_;

  $self->_check_object();

  unless ($params && $$params{filename}) {
    croak 'You must pass in hash params that contain a filename argument';
  }

  open FILE, "<", $$params{filename} or croak $!;
  my $content = do { local( $/ ) ; <FILE> } ;

  my $html;
  if (defined($$params{charset}) && $$params{charset} && find_encoding($$params{charset}) ) {
    $html = decode($$params{charset}, $content);
  }
  else {
    $html = $content; # best we can do, no encoding specified
  }

  $self->read({ html => $html });

  return();
}

=pod

=item read

Reads passed html data and parses it.  The intermediate data is stored in
class variables.

The <style> block is ripped out of the html here, and stored
separately. Class/ID/Names used in the markup are left alone.

This method requires you to pass in a params hash that contains scalar
html data. For example:

$self->read({ html => $html });

NOTE: You are required to pass a properly encoded perl reference to the
html data. This method does *not* do the dirty work of encoding the html
as utf8 - do that before calling this method.

=cut

sub read {
  my ($self,$params) = @_;

  $self->_check_object();

  unless ($params && $$params{html}) {
    croak 'You must pass in hash params that contains html data';
  }

  $self->_html_tree->parse_content($$params{html});

  $self->_init_query();

  #suck in the styles for later use from the head section - stylesheets anywhere else are invalid
  my $stylesheet = $self->_parse_stylesheet();

  #save the data
  $self->_html($$params{html});
  $self->_stylesheet($stylesheet);

  return();
}

=pod

=item inlinify

Processes the html data that was entered through either 'read' or
'read_file', returns a scalar that contains a composite chunk of html
that has inline styles instead of a top level <style> declaration.

=cut

sub inlinify {
  my ($self,$params) = @_;

  $self->_check_object();

  $self->_content_warnings({}); # overwrite any existing warnings

  unless ($self->_html() && $self->_html_tree()) {
    croak 'You must instantiate and read in your content before inlinifying';
  }

  # perform a check to see how bad this html is...
  $self->_validate_html({ html => $self->_html() });

  my $html;
  if (defined $self->_css()) {
    #parse and store the stylesheet as a hash object

    $self->_css->read({ css => $self->_stylesheet() });

    my @css_warnings = @{$self->_css->content_warnings()};
    foreach my $css_warning (@css_warnings) {
      $self->_report_warning({ info => $css_warning });
    }

    my %matched_elements;
    my $count = 0;

    foreach my $entry (@{$self->_css->get_rules()}) {
      next unless exists $$entry{selector} && $$entry{declarations};

      my $selector = $$entry{selector};
      my $declarations = $$entry{declarations};

      #skip over the following psuedo selectors, these particular ones are not inlineable
      if ($selector =~ /(?:^|[\w\*]):(?:(active|focus|hover|link|visited|after|before|selection|target|first-line|first-letter))\b/io) {
        $self->_report_warning({ info => "The pseudo-class ':$1' cannot be supported inline" });
        next;
      }

      #skip over @import or anything else that might start with @ - not inlineable
      if ($selector =~ /^\@/io) {
        $self->_report_warning({ info => "The directive '$selector' cannot be supported inline" });
        next;
      }

      my $query_result;

      #check to see if query fails, possible for jacked selectors
      eval {
        $query_result = $self->query({ selector => $selector });
      };

      if ($@) {
        $self->_report_warning({ info => $@->info() });
        next;
      }

      # CSS rules cascade based on the specificity and order
      my $specificity = $self->specificity({ selector => $selector });

      #if an element matched a style within the document store the rule, the specificity
      #and the actually CSS attributes so we can inline it later
      foreach my $element (@{$query_result->get_elements()}) {

       $matched_elements{$element->address()} ||= [];
        my %match_info = (
          rule     => $selector,
          element  => $element,
          specificity   => $specificity,
          position => $count,
          css      => $declarations
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
        my $cur_style = $self->_split({ style => $element->attr('style') });
        %new_style = (%new_style, %{$cur_style});
      }

      $element->attr('style', $self->_expand({ declarations => \%new_style }));
    }

    #at this point we have a document that contains the expanded inlined stylesheet
    #BUT we need to collapse the declarations to remove duplicate overridden styles
    $self->_collapse_inline_styles();

    # The entities list is the do-not-encode string from HTML::Entities
    # with the single quote added.

    # 3rd argument overrides the optional end tag, which for HTML::Element
    # is just p, li, dt, dd - tags we want terminated for our purposes

    $html = $self->_html_tree->as_HTML(q@^\n\r\t !\#\$%\(-;=?-~'@,' ',{});
  }
  else {
    $html = $self->{html};
  }

  return $html . "\n";
}

=pod

=item query

Given a particular selector return back the applicable styles

=cut

sub query {
  my ($self,$params) = @_;

  $self->_check_object();

  unless ($self->_query()) {
    $self->_init_query();
  }

  return $self->_query->query($$params{selector});
}

=pod

=item specificity

Given a particular selector return back the associated selectivity

=cut

sub specificity {
  my ($self,$params) = @_;

  $self->_check_object();

  unless ($self->_query()) {
    $self->_init_query();
  }

  return $self->_query->get_specificity($$params{selector});
}

=pod

=item content_warnings

Return back any warnings thrown while inlining a given block of content.

Note: content warnings are initialized at inlining time, not at read time. In
order to receive back content feedback you must perform inlinify first

=back

=cut

sub content_warnings {
  my ($self,$params) = @_;

  $self->_check_object();

  my @content_warnings = keys %{$self->_content_warnings()};

  return \@content_warnings;
}

####################################################################
#                                                                  #
# The following are all private methods and are not for normal use #
# I am working to finalize the get/set methods to make them public #
#                                                                  #
####################################################################


sub _check_object {
  my ($self, $params) = @_;

  unless (ref $self) {
   croak 'You must instantiate this class in order to properly use it';
  }

  return ();
}

sub _report_warning {
  my ($self,$params) = @_;

  $self->_check_object();

  if ($self->_warns_as_errors()) {
    croak $$params{info};
  }
  else {
    my $warnings = $self->_content_warnings();
    $$warnings{$$params{info}} = 1;
  }

  return();
}

sub _fetch_url {
  my ($self,$params) = @_;

  $self->_check_object();

  # Create a user agent object
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/4.0'); # masquerade as Mozilla/4.0
  $ua->protocols_allowed( ['http','https'] );

  # Create a request
  my $uri = URI->new($$params{url});

  my $req = HTTP::Request->new('GET',$uri);

  # Pass request to the user agent and get a response back
  my $res = $ua->request($req);

  # if not successful
  if (!$res->is_success()) {
    croak 'There was an error in fetching the document for ' . $uri . ' : ' . $res->message;
  }

  # Is it a HTML document
  if ($res->content_type ne 'text/html' && $res->content_type ne 'text/css') {
    croak 'The web site address you entered is not an HTML document.';
  }

  my $content;
  if ($res->content_type_charset && find_encoding($res->content_type_charset)->name) {
    $content = decode($res->content_type_charset, $res->content || '');
  }
  else {
    $content = $res->content || ''; # best we can do, no encoding given
  }

  # Expand all URLs to absolute ones
  my $baseref = $res->base;

  return ($content,$baseref);
}

sub _fetch_html {
  my ($self,$params) = @_;

  $self->_check_object();

  my $url = ($$params{url} =~ m/^https?:\/\//) ? $$params{url} : 'http://' . $$params{url};

  my ($content,$baseref) = $self->_fetch_url({ url => $url });

  # Build "relaxed" HTML tree using internal treebuilder - we want to return html that is as
  # close to the original as possible. We can more strictly parse this later if necessary
  my $doc = CSS::Inliner::TreeBuilder->new();
  $doc->store_comments(1);
  $doc->ignore_unknown(0);
  $doc->implicit_tags(0);
  $doc->parse_content($content);

  # Change relative links to absolute links
  $self->_changelink_relative({ content => $doc->content, baseref => $baseref });

  $self->_expand_stylesheet({ content => $doc, html_baseref => $baseref });

  my $html = $doc->as_HTML(q@^\n\r\t !\#\$%\(-;=?-~'@,' ',{});

  return $html;
}

sub _changelink_relative {
  my ($self,$params) = @_;

  $self->_check_object();

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

sub __fix_relative_url {
  my ($self,$params) = @_;

  $self->_check_object();

  my $uri = URI->new($$params{url});

  return $$params{prefix} . "'" . $uri->abs($$params{base})->as_string ."'";
}

sub _expand_stylesheet {
  my ($self,$params) = @_;

  $self->_check_object();

  my $doc = $$params{content};

  my $stylesheets = ();

  my (@style,@link);
  if ($self->_relaxed()) {
    #get the <style> nodes
    @style = $doc->look_down('_tag','style');

    #get the <link> nodes
    @link = $doc->look_down('_tag','link','href',qr/./);
  }
  else {
    #get the head section of the document
    my $head = $doc->look_down('_tag', 'head'); # there should only be one

    #get the <style> nodes underneath the head section - that's the only place stylesheets are allowed to live
    @style = $head->look_down('_tag','style');

    #get the <link> nodes underneath the head section - there should be *none* at this step in the process
    @link = $head->look_down('_tag','link','href',qr/./);
  }

  foreach my $i (@link) {
    # determine attribute values for the link tag, assign some defaults to avoid comparison warnings later
    my $rel = defined($i->attr('rel')) ? $i->attr('rel') : '';
    my $type = defined($i->attr('type')) ? $i->attr('type') : '';
    my $href = defined($i->attr('href')) ? $i->attr('href') : '';

    # if we don't match the signature of an inlineable stylesheet, skip over
    next unless (($rel eq 'stylesheet') || ($type eq 'text/css') || ($href =~ m/\.css$/));

    my ($content,$baseref) = $self->_fetch_url({ url => $i->attr('href') });

    #absolutized the assetts within the stylesheet that are relative
    $content =~ s/(url\()["']?((?:(?!https?:\/\/)(?!\))[^"'])*)["']?(?=\))/$self->__fix_relative_url({ prefix => $1, url => $2, base => $baseref })/exsgi;

    my $stylesheet = HTML::Element->new('style', type => 'text/css', rel=> 'stylesheet');
    $stylesheet->push_content($content);

    $i->replace_with($stylesheet);
  }

  foreach my $i (@style) {
    #use the baseref from the original document fetch
    my $baseref = $$params{html_baseref};

    my @content = $i->content_list();
    my $content = join('',grep {! ref $_ } @content);

    # absolutize the assets within the stylesheet that are relative
    $content =~ s/(url\()["']?((?:(?!https?:\/\/)(?!\))[^"'])*)["']?(?=\))/$self->__fix_relative_url({ prefix => $1, url => $2, base => $baseref })/exsgi;

    my $stylesheet = HTML::Element->new('style', type => 'text/css', rel=> 'stylesheet');
    $stylesheet->push_content($content);

    $i->replace_with($stylesheet);
  }

  return();
}

sub _validate_html {
  my ($self,$params) = @_;

  my $validator_tree = new CSS::Inliner::TreeBuilder();
  $validator_tree->ignore_unknown(0);
  $validator_tree->implicit_tags(0);
  $validator_tree->parse_content($$params{html});

  if ($self->_relaxed()) {
    # TODO: print out any html issues that would cause the relaxed parsing to modify the document or might cause
    # a rendering problem of some type
    #
    # Currently there are no known issues, but when found they would go here
  }
  else {
    # The following are inconsistencies that can easily be found by scanning our document using the internal Treebuilder
    # The standard TreeBuilder actually alters the document in an attempt to create something "valid", but by doing so
    # all sorts of weird things can happen, so we add them to the warnings report so the caller knows what's going on.

    # count up the major structural components of the document
    my @html_nodes = $validator_tree->look_down('_tag', 'html');
    my @head_nodes = $validator_tree->look_down('_tag', 'head');
    my @body_nodes = $validator_tree->look_down('_tag', 'body');

    # we should have exactly 2 root nodes, the treebuilder inserted one and the nested one from the document...
    if (scalar @html_nodes == 0) {
      $self->_report_warning({ info => 'Unexpected absence of html root node, force inserted' });
    }
    elsif (scalar @html_nodes > 1) {
      $self->_report_warning({ info => 'Unexpected spurious html root node(s) found within referenced document, coalesced' });
    }

    if (scalar @head_nodes > 1) {
      $self->_report_warning({ info => 'Unexpected spurious head node(s) found within referenced document, coalesced' });
    }

    if (scalar @body_nodes > 1) {
      $self->_report_warning({ info => 'Unexpected spurious body node(s) found within referenced document, coalesced' });
    }

    my @link = $validator_tree->look_down('_tag','link','href',qr/./);

    foreach my $i (@link) {
      my $rel = defined($i->attr('rel')) && $i->attr('rel') ? $i->attr('rel') : '';
      my $type = defined($i->attr('type')) && $i->attr('type') ? $i->attr('type') : '';
      my $href = defined($i->attr('href')) && $i->attr('href') ? $i->attr('href') : '';

      # link references to stylesheets at this point in the workflow means the caller is doing something improper
      # currently such references are only chased down if you fetch a document, not if you feed one in
      if ($rel eq 'stylesheet' || $type eq 'text/css' || $href =~ m/.css$/) {
        $self->_report_warning({ info => 'Unexpected reference to remote stylesheet was not inlined' });
        last;
      }
    }

    my $body = $self->_html_tree->look_down('_tag', 'body');

    if ($body) {
      # located spurious <style> tags that won't be handled
      my @spurious_style = $body->look_down('_tag','style','type','text/css');

      if (scalar @spurious_style) {
        $self->_report_warning({ info => 'Unexpected reference to stylesheet within document body skipped' });
      }
    }
  }

  return();
}

sub _parse_stylesheet {
  my ($self,$params) = @_;

  $self->_check_object();

  my $stylesheet = '';

  # figure out where to look for styles
  my $stylesheet_root = $self->_relaxed() ? $self->_html_tree() : $self->_html_tree->look_down('_tag', 'head');

  # get the <style> nodes
  my @style = $stylesheet_root->look_down('_tag','style','type','text/css');

  foreach my $i (@style) {
    #process this node if the html media type is screen, all or undefined (which defaults to screen)
    if (($i->tag eq 'style') && (!$i->attr('media') || $i->attr('media') =~ m/\b(all|screen)\b/)) {

      foreach my $item ($i->content_list()) {
        # remove HTML comment markers
        $item =~ s/<!--//mg;
        $item =~ s/-->//mg;

        $stylesheet .= $item;
      }
    }

    unless ($self->_leave_style()) {
      $i->delete();
    }
  }

  return $stylesheet;
}

sub _collapse_inline_styles {
  my ($self,$params) = @_;

  $self->_check_object();

  #check if we were passed a node to recurse from, otherwise use the root of the tree
  my $content = exists($$params{content}) ? $$params{content} : [$self->_html_tree()];

  foreach my $i (@{$content}) {

    next unless (ref $i && $i->isa('HTML::Element'));

    if ($i->attr('style')) {

      #flatten out the styles currently in place on this entity
      my $existing_styles = $i->attr('style');
      $existing_styles =~ tr/\n\t/  /;

      # hold the property value pairs
      my $styles = $self->_split({ style => $existing_styles });

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
      $self->_collapse_inline_styles({ content => $i->content() });
    }
  }
}

sub _init_query {
  my ($self,$params) = @_;

  $self->_check_object();

  $self->{query} = HTML::Query->new($self->_html_tree());

  return();
}

sub _expand {
  my ($self, $params) = @_;

  $self->_check_object();

  my $declarations = $$params{declarations};
  my $inline = '';
  foreach my $property (keys %{$declarations}) {
    $inline .= $property . ':' . $$declarations{$property} . ';';
  }

  return $inline;
}

sub _split {
  my ($self, $params) = @_;

  $self->_check_object();

  my $style = $params->{style};
  my %split;

  # Split into properties/values
  foreach ( grep { /\S/ } split /\;/, $style ) {
    unless ( /^\s*([\w._-]+)\s*:\s*(.*?)\s*$/ ) {
      $self->_report_warning({ info => "Invalid or unexpected property '$_' in style '$style'" });
    }
    $split{lc $1} = $2;
  }

  return \%split;
}

1;

=pod

=head1 Sponsor

This code has been developed under sponsorship of MailerMailer LLC,
http://www.mailermailer.com/

=head1 AUTHOR

Kevin Kamel <kamelkev@mailermailer.com>

=head1 CONTRIBUTORS

Vivek Khera <vivek@khera.org>, Michael Peters <wonko@cpan.org>

=head1 LICENSE

This module is Copyright 2013 Khera Communications, Inc.  It is
licensed under the same terms as Perl itself.

=cut
