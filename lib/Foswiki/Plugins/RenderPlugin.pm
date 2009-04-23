# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/

# Copyright (C) 2008-2009 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::RenderPlugin;

require Foswiki::Func;
require Foswiki::Sandbox;
use strict;

use vars qw( $VERSION $RELEASE $SHORTDESCRIPTION $NO_PREFS_IN_TOPIC );

$VERSION = '$Rev$';
$RELEASE = '2.0';

$SHORTDESCRIPTION = 'Render <nop>WikiApplications asynchronously';
$NO_PREFS_IN_TOPIC = 1;

use constant DEBUG => 0; # toggle me

###############################################################################
sub writeDebug {
  print STDERR '- RenderPlugin - '.$_[0]."\n" if DEBUG;
}


###############################################################################
sub initPlugin {
  my ($topic, $web, $user, $installWeb) = @_;

  Foswiki::Func::registerRESTHandler('tag', \&restTag);
  Foswiki::Func::registerRESTHandler('expand', \&restExpand);
  Foswiki::Func::registerRESTHandler('render', \&restRender);
  Foswiki::Func::registerRESTHandler('upload', \&restUpload);

  return 1;
}

###############################################################################
sub restRender {
  my ($session, $subject, $verb) = @_;

  my $query = Foswiki::Func::getCgiQuery();
  my $theTopic = $query->param('topic') || $session->{topicName};
  my $theWeb = $query->param('web') || $session->{webName};
  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);

  return Foswiki::Func::renderText(restExpand($session, $subject, $verb), $web);
}

###############################################################################
sub restExpand {
  my ($session, $subject, $verb) = @_;

  # get params
  my $query = Foswiki::Func::getCgiQuery();
  my $theText = $query->param('text') || '';

  return ' ' unless $theText; # must return at least on char as we get a
                              # premature end of script otherwise
                              
  my $theTopic = $query->param('topic') || $session->{topicName};
  my $theWeb = $query->param('web') || $session->{webName};
  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);

  # and render it
  return Foswiki::Func::expandCommonVariables($theText, $topic, $web) || ' ';
}

###############################################################################
sub restTag {
  my ($session, $subject, $verb) = @_;

  #writeDebug("called restTag($subject, $verb)");

  # get params
  my $query = Foswiki::Func::getCgiQuery();
  my $theTag = $query->param('name') || 'INCLUDE';
  my $theDefault = $query->param('param') || '';
  my $theRender = $query->param('render') || 0;

  $theRender = ($theRender =~ /^\s*(1|on|yes|true)\s*$/) ? 1:0;

  my $theTopic = $query->param('topic') || $session->{topicName};
  my $theWeb = $query->param('web') || $session->{webName};
  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);

  # construct parameters for tag
  my $params = $theDefault?'"'.$theDefault.'"':'';
  foreach my $key ($query->param()) {
    next if $key =~ /^(name|param|render|topic|XForms:Model)$/;
    my $value = $query->param($key);
    $params .= ' '.$key.'="'.$value.'" ';
  }

  # create TML expression
  my $tml = '%'.$theTag;
  $tml .= '{'.$params.'}' if $params;
  $tml .= '%';

  #writeDebug("tml=$tml");

  # and render it
  my $result = Foswiki::Func::expandCommonVariables($tml, $topic, $web) || ' ';
  if ($theRender) {
    $result = Foswiki::Func::renderText($result, $web);
  }

  #writeDebug("result=$result");

  return $result;
}

###############################################################################
sub restUpload {
  my ($session, $subject, $verb) = @_;

  my $query = Foswiki::Func::getCgiQuery();
  my $topic = $query->param('topic');
  my $web;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName("", $topic);

  my $hideFile = $query->param('hidefile') || '';
  my $fileComment = $query->param('filecomment') || '';
  my $createLink = $query->param('createlink') || '';
  my $doPropsOnly = $query->param('changeproperties');
  my $filePath = $query->param('filepath') || '';
  my $fileName = $query->param('filename') || '';
  if ($filePath && ! $fileName) {
      $filePath =~ m|([^/\\]*$)|;
      $fileName = $1;
  }
  $fileComment =~ s/\s+/ /go;
  $fileComment =~ s/^\s*//o;
  $fileComment =~ s/\s*$//o;
  $fileName =~ s/\s*$//o;
  $filePath =~ s/\s*$//o;

  unless (Foswiki::Func::checkAccessPermission(
      'CHANGE', Foswiki::Func::getWikiName(), undef, $topic, $web)) {
      return "Access denied";
  }

  my ($fileSize, $fileDate, $tmpFileName);

  my $stream = $query->upload('filepath') unless $doPropsOnly;
  my $origName = $fileName;

  unless($doPropsOnly) {
      # SMELL: call to unpublished function
      ($fileName, $origName) =
        Foswiki::Sandbox::sanitizeAttachmentName($fileName);

      # check if upload has non zero size
      if($stream) {
          my @stats = stat $stream;
          $fileSize = $stats[7];
          $fileDate = $stats[9];
      }

      unless($fileSize && $fileName) {
          return "Zero-sized file upload";
      }

      my $maxSize = Foswiki::Func::getPreferencesValue(
          'ATTACHFILESIZELIMIT');
      $maxSize = 0 unless ($maxSize =~ /([0-9]+)/o);

      if ($maxSize && $fileSize > $maxSize * 1024) {
          return "Oversized upload";
      }
  }

  # SMELL: use of undocumented CGI::tmpFileName
  my $tfp = $query->tmpFileName($query->param('filepath'));
  my $dontlog = $Foswiki::cfg{Log}{upload};
  $dontlog = $Foswiki::cfg{Log}{upload} unless defined $dontlog;
  my $error = Foswiki::Func::saveAttachment(
      $web, $topic, $fileName,
      {
          dontlog => !$dontlog,
          comment => $fileComment,
          hide => $hideFile,
          createlink => $createLink,
          stream => $stream,
          filepath => $filePath,
          filesize => $fileSize,
          filedate => $fileDate,
          tmpFilename => $tfp,
      });

  close($stream) if $stream;

  return $error if $error;

  # Otherwise allow the rest dispatcher to write a 200
  return 
    "$origName attached to $web.$topic" . 
    ($origName ne $fileName ?" as $fileName" : '');
}

1;
