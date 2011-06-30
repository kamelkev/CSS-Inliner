# $Id: Simpler.pm -1   $
#
# Copyright 2011 MailerMailer, LLC - http://www.mailermailer.com
#
# Based in large part on the CSS::Tiny CPAN Module
# http://search.cpan.org/~adamk/CSS-Tiny/
#
# This is version 2 of this module, which concerns itself with very strictly preserving ordering of rules,
# something that has been the focus of this module series from the beginning. We focus more on preservation
# of rule ordering than we do on ease of modifying enclosed rules. If you are attempting to modify 
# rules through an API please see CSS::Simple

package CSS::Inliner::Parser;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = sprintf "%d", q$Revision: -1 $ =~ /(\d+)/;

use Carp;

use Storable qw(dclone);

=pod

=head1 NAME

CSS::Inliner::Parser - Interface through which to read/write CSS files while respecting the cascade order

NOTE: This sub-module very seriously focuses on respecting cascade order. As such this module is not for you
      if you want to modified a stylesheet once it's read. If you are looking for that functionality you may
      want to look at the sister module, CSS::Simple

=head1 SYNOPSIS

 use CSS::Inliner::Parser;

 my $css = new CSS::Inliner::Parser();

 $css->read({ filename => 'input.css' });

 #perform manipulations...

 $css->write({ filename => 'output.css' });

=head1 DESCRIPTION

Class for reading and writing CSS. Unlike other CSS classes on CPAN this particular module
focuses on respecting the order of selectors. This is very useful for things like... inlining
CSS, or for similar "strict" CSS work.

=cut

BEGIN {
  my $members = ['ordered','stylesheet','warns_as_errors','content_warnings'];

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

=head1 CONSTRUCTOR

=over 4

=item new ([ OPTIONS ])

Instantiates the CSS::Inliner::Parser object. Sets up class variables that are used during file parsing/processing.

B<warns_as_errors> (optional). Boolean value to indicate whether fatal errors should occur during parse failures.

=back

=cut

sub new {
  my ($proto, $params) = @_;

  my $class = ref($proto) || $proto;

  my $entries = [];
  my $selectors = {};

  my $self = {
              stylesheet => undef,
              ordered => $entries,
              selectors => $selectors,
              content_warnings => undef,
              warns_as_errors => (defined($$params{warns_as_errors}) && $$params{warns_as_errors}) ? 1 : 0
             };

  bless $self, $class;
  return $self;
}

=head1 METHODS

=cut

=pod

=over 4

=item read_file( params )

Opens and reads a CSS file, then subsequently performs the parsing of the CSS file
necessary for later manipulation.

This method requires you to pass in a params hash that contains a
filename argument. For example:

$self->read_file({filename => 'myfile.css'});

=cut

sub read_file {
  my ($self,$params) = @_;

  $self->_check_object();

  unless ($params && $$params{filename}) {
    croak "You must pass in hash params that contain a filename argument";
  }

  open FILE, "<", $$params{filename} or croak $!;
  my $css = do { local( $/ ) ; <FILE> } ;

  $self->read({css => $css});

  return();
}

=pod

=item read( params )

Reads css data and parses it. The intermediate data is stored in class variables.

Compound selectors (i.e. "a, span") are split apart during parsing and stored
separately, so the output of any given stylesheet may not match the output 100%, but the 
rules themselves should apply as expected.

This method requires you to pass in a params hash that contains scalar
css data. For example:

$self->read({css => $css});

=cut

sub read {
  my ($self,$params) = @_;

  $self->_check_object();

  $self->_content_warnings({}); # overwrite any existing warnings

  unless (exists $$params{css}) {
    croak 'You must pass in hash params that contains the css data';
  }

  if ($params && $$params{css}) {
    # Flatten whitespace and remove /* comment */ style comments
    my $string = $$params{css};
    $string =~ tr/\n\t/  /;
    $string =~ s!/\*.*?\*\/!!g;

    # Split into styles
    foreach ( grep { /\S/ } split /(?<=\})/, $string ) {

      unless ( /^\s*([^{]+?)\s*\{(.*)\}\s*$/ ) {
        $self->_report_warning({ info => "Invalid or unexpected style data '$_'" });
        next;
      }

      # Split in such a way as to support grouped styles
      my $rule = $1;
      my $props = $2;

      $rule =~ s/\s{2,}/ /g;

      # Split into properties
      my $properties = {};
      foreach ( grep { /\S/ } split /\;/, $props ) {

        # skip over browser specific properties
        if ((/^\s*[\*\-\_]/) || (/\\/)) {
          next; 
        }

        # check if properties are valid, reporting error as configured        
        unless ( /^\s*([\w._-]+)\s*:\s*(.*?)\s*$/ ) {
          $self->_report_warning({ info => "Invalid or unexpected property '$_' in style '$rule'" });
          next;
        }

        #store the property for later
        $$properties{lc $1} = $2;
      }

      my @selectors = split /,/, $rule; # break the rule into the component selector(s)

      #apply the found rules to each selector
      foreach my $selector (@selectors) {
        $selector =~ s/^\s+|\s+$//g;

        $self->add_selector({selector => $selector, properties => $properties});
      }
    }
  }
  else {
    $self->_report_warning({ info => 'No stylesheet data was found in the document'});
  }

  return();
}

=pod

=item write_file()

Write the parsed and manipulated CSS out to a file parameter

This method requires you to pass in a params hash that contains a
filename argument. For example:

$self->write_file({filename => 'myfile.css'});

=cut

sub write_file {
  my ($self,$params) = @_;

  $self->_check_object();

  unless (exists $$params{filename}) {
    croak "No filename specified for write operation";
  }

  # Write the file
  open( CSS, '>'. $$params{filename} ) or croak "Failed to open file '$$params{filename}' for writing: $!";
  print CSS $self->write();
  close( CSS );

  return();
}

=pod

=item write()

Write the parsed and manipulated CSS out to a scalar and return it

=cut

sub write {
  my ($self,$params) = @_;

  $self->_check_object();

  my $contents = '';

  foreach my $entry ( @{$self->_ordered()} ) {

    #grab the properties that make up this particular selector
    my $properties = $$entry{properties};
    my $selector = $$entry{selector};

    $contents .= "$selector {\n";
    foreach my $property ( sort keys %{ $properties } ) {
      $contents .= "\t" . lc($property) . ": ".$properties->{$property}. ";\n";
    }
    $contents .= "}\n";
  }

  return $contents;
}

=pod
    
=item content_warnings()
 
Return back any warnings thrown while parsing a given block of css

Note: content warnings are initialized at read time. In order to 
receive back content feedback you must perform read() first.

=cut

sub content_warnings {
  my ($self,$params) = @_;

  $self->_check_object();

  my @content_warnings = keys %{$self->_content_warnings()};

  return \@content_warnings;
}

####################################################################
#                                                                  #
# The following are all get/set methods for manipulating the       #
# stored stylesheet                                                #
#                                                                  #
####################################################################

=pod

=item get_entries( params )

Get an array of entries representing the composition of the stylesheet. These entries
are returned in the exact order that they were discovered.

An entry is composed of a hash with a structure like the following:

$entry = { selector => '.my_selector', properties => { attribute => 'value' } }

=cut

sub get_entries {
  my ($self,$params) = @_;

  $self->_check_object();

  return $self->_ordered();
}

=pod

=item add_entry( params )

Add an entry containing a selector and associated properties to the stored rulesets

This method requires you to pass in a params hash that contains scalar
css data. For example:

$self->add_selector({selector => '.foo', properties => {color => 'red' }});

=cut

sub add_selector {
  my ($self,$params) = @_;

  $self->_check_object();

  my $entry = { selector => $$params{selector}, properties => $$params{properties} };

  push @{$self->_ordered()}, $entry;

  return $entry;
}

####################################################################
#                                                                  #
# The following are all private methods and are not for normal use #
# I am working to finalize the get/set methods to make them public #
#                                                                  #
####################################################################

sub _check_object {
  my ($self,$params) = @_;

  unless ($self && ref $self) {
    croak "You must instantiate this class in order to properly use it";
  }

  return();
}

sub _report_warning {
  my ($self,$params) = @_;

  $self->_check_object();

  if ($self->{warns_as_errors}) {
    croak $$params{info};
  }
  else {
    my $warnings = $self->_content_warnings();
    $$warnings{$$params{info}} = 1;
  }

  return();
}

1;

=pod

=head1 Sponsor

This code has been developed under sponsorship of MailerMailer LLC, http://www.mailermailer.com/

=head1 AUTHOR

Kevin Kamel <C<kamelkev@mailermailer.com>>

=head1 ATTRIBUTION

This module is directly based off of Adam Kennedy's <adamk@cpan.org> CSS::Tiny module.

This particular version differs in terms of interface and the ultimate ordering of the CSS.

=head1 LICENSE

This module is a derived version of Adam Kennedy's CSS::Tiny Module.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=cut
