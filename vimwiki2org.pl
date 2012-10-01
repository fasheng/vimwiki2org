#! /usr/bin/perl -w

# vimwiki2org.pl ---

# Filename: vimwiki2org.pl
# Description:
# Author: Xu FaSheng
# Maintainer: Xu FaSheng
# Created: Sat Sep 29 17:39:10 2012 (+0800)
# Version: 0.1
# Last-Updated:
#           By:
#     Update #: 0
# URL:
# Keywords: vimwiki org org-mode
# Compatibility:
#   test ok on vimwiki 2.0.1.stu
#   need perl 5.14

# Commentary:
#
# This is a simple tool to convert vimwiki files to org-mode file, and the
# usage is simple:
# perl vimwiki2org.pl index.wiki > vimwiki.org
#
# more information to see help: TODO
# perl vimwiki2org.pl --help
#

# Change Log:
# - 0.1
#   + create
#
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 3, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING.  If not, write to
# the Free Software Foundation, Inc., 51 Franklin Street, Fifth
# Floor, Boston, MA 02110-1301, USA.
#
#

# Code:


use 5.014;
use autodie qw/open close/;
use List::Util qw/first/;
use File::Basename;
use File::Spec;
# TODO, getopt

my $org_commit = "#";           # TODO

# add org file tags
my $org_file_tags = "vimwiki";
say $org_commit, '+FILETAGS: :', $org_file_tags, ":";

# the vimwiki index file
my $index_file = shift @ARGV;
$index_file = File::Spec->canonpath($index_file);
my $vimwiki_base_dir = dirname $index_file;

# the vimwiki diary index file, not necessary TODO
my $diary_index_file = &build_path($vimwiki_base_dir, "diary/diary.wiki");

# options TODO
my $ignore_lonely_header = 1;
# $ignore_file_list
# my $list_max_level_to_org_headline = 1;
my $log_file = "/tmp/vimwiki2org.log";
my $log_fh;

# other variables
my $vimwiki_ext = '.wiki';
my @dispatched_files;
my @open_error_files;

# links in vimwiki
# such as '[[file]] [[file|name]]'
my $link_regexp = '\[\[(.*?)\]\]';

# commit and placeholder of vimwiki, which all start with "%"
# such as "%title", "%% commit"
my $commit_regexp = '^\s*%';

# headers in vimwiki
# such as "=== header ==="
my $header_regexp = '^(=+) ?(.*) ?\1$';

# lists in vimwiki
# such as "* list", "- list", "# list"
my $list_regexp = '^(\s*)([#*-]) (.*)$';

# plain text in vimwiki
my $plain_regexp = '^(\s*)(.*)$';

# main content
&open_log();
&open_and_dispatch($index_file);
&close_log();

sub build_path {
    my $path = File::Spec->catfile(@_);
    File::Spec->canonpath($path); # clean up path
}

sub open_log {
    eval {open $log_fh, ">", $log_file};
    warn $@ if ($@);
    &append_log("# ERROR MESSAGE");
}

sub append_log {
    my $msg = shift;
    say {$log_fh} $msg if (defined $log_fh);
}

sub close_log {
    &append_log("\n# DISPATCHED FILES");
    &append_log($_) foreach (@dispatched_files);
    &append_log("\n# OPEN FAILED FILES");
    &append_log($_) foreach (@open_error_files);
    eval {close $log_fh};
}

# main function
sub open_and_dispatch {
    my $vimwiki_file = shift @_;
    my $org_parent_lv = shift @_ // 0;

    # ignore repeated files
    return if (@dispatched_files ~~ /^\Q$vimwiki_file\E$/);
    push @dispatched_files, $vimwiki_file;

    my @content;
    eval {
        open my $fh, "<", $vimwiki_file;
        @content = <$fh>;
        close $fh;
    };
    if ($@) {
        # catch error
        push @open_error_files, $vimwiki_file;
        &append_log($@);
        return;
    }
    chomp(@content);

    # count headers in vimwiki
    my $header_count = grep /$header_regexp/, @content;

    # find the minimum header level in current file, and set it as
    # the start org level, for example, the minimus header level is 3,
    # like "=== header ===", if not think of its parent level, it will be
    # convert to a org header as level 1, like "* header"
    my @headers = grep /$header_regexp/, @content;
    my $min_header_lv = length((shift @headers) =~ s/$header_regexp/$1/r);
    foreach(@headers) {
        my $header_lv = length(s/$header_regexp/$1/r);
        if($header_lv < $min_header_lv) {
            $min_header_lv = $header_lv;
        }
    }

    ## dispatch the content

    # links under current org headline
    my @collected_links = ();
    my $last_org_headline_lv = $org_parent_lv;

    # my $cur_header_org_lv = $org_parent_lv;# TODO
    my $org_parent_lv_for_following_list = $org_parent_lv;
    # remember the first list item's prefix space count in a header
    # use this to judge if a list is first level under the header
    my $first_list_pre_spc_count = undef;

    foreach(@content) {
        # links in vimwiki
        when (/$link_regexp/) {
            # collect links in current line, and these links will be expand
            # before next org headline output, in another hand, they will
            # be append at the end of current org headline(if exist)
            $_ = &collect_links_and_format_cur_line($_, \@collected_links,
                                                     $vimwiki_file);
            continue;
        }

        # commit and placeholder of vimwiki, which all start with "%"
        when (/$commit_regexp/) {
            say "# ", $_;
            next;
        }

        # headers in vimwiki
        when (/$header_regexp/) {
            &expand_collected_links(\@collected_links, $last_org_headline_lv);

            # reset markers
            $first_list_pre_spc_count = undef;

            if($ignore_lonely_header) {
                # if there is only one header, ignore it
                if($header_count <= 1){
                    say $org_commit, $_;
                    next;
                }
            }

            # output as a org headline
            my $header_lv = length(s/$header_regexp/$1/r);
            my $header_text = s/$header_regexp/$2/r;
            my $org_headline_lv =
                &compute_org_headline_lv($header_lv, $min_header_lv,
                                         $org_parent_lv);
            say &build_org_headline($header_text, $org_headline_lv);

            # mark current header's org level as
            # the following list's parent org level
            $org_parent_lv_for_following_list = $org_headline_lv;
            $last_org_headline_lv = $org_headline_lv;
        }

        # lists in vimwiki
        when (/$list_regexp/) {
            my $list_pre_spc_count = length(s/$list_regexp/$1/r);
            my $list_text = s/$list_regexp/$3/r;
            if(!defined($first_list_pre_spc_count)) {
                $first_list_pre_spc_count = $list_pre_spc_count;
            }
            if($list_pre_spc_count <= $first_list_pre_spc_count) {
                # this list item could be convert to a org headline
                &expand_collected_links(\@collected_links, $last_org_headline_lv);

                my $org_headline_lv = $org_parent_lv_for_following_list + 1;

                # convert TODO state, '[X]' -> 'DONE', '[.]' or '[ ]' -> 'TODO'
                my $org_headline_text = $list_text =~ s/\[X\]/DONE/r;
                $org_headline_text = $org_headline_text =~ s/\[.\]/TODO/r;
                say &build_org_headline($org_headline_text, $org_headline_lv);
                $last_org_headline_lv = $org_headline_lv;
            } else {
                # this list item could be convert to a org plain list
                # simple align text, and convert all item placeholder to '-'
                # such as '[#-*] ' -> '- '
                my $aligned_pre_spc_count = $list_pre_spc_count
                    - $first_list_pre_spc_count
                    + $org_parent_lv_for_following_list;
                my $aligned_pre_spc = " " x $aligned_pre_spc_count;
                s/$list_regexp/$aligned_pre_spc- $3/;
                say;
            }
        }

        # plain text
        default {
            #align text TODO
            # my $plain_pre_spc_count = length(s/$plain_regexp/$1/r);

            # convert source code:
            # '{{{' -> '#begin_src', '{{{sh' -> '#begin_src sh'
            s/({{{)/#begin_src /;
            s/(}}})/#end_src /;
            say;
        };
    }
    &expand_collected_links(\@collected_links, $last_org_headline_lv);

}

sub compute_org_headline_lv {
    my $header_lv = shift;
    my $min_header_lv = shift;
    my $org_parent_lv = shift;

    my $org_headline_lv = $header_lv - $min_header_lv + 1;
    $org_headline_lv += $org_parent_lv;
    if ($org_headline_lv <= 0) {$org_headline_lv = 1;}
    $org_headline_lv;
}

sub build_org_headline {
    my $org_headline_text = shift;
    my $org_headline_lv = shift;
    my $org_headline = "*" x $org_headline_lv . " " . $org_headline_text;
}

# collect links under current org headline
# and convert link format to org type
sub collect_links_and_format_cur_line {
    my $line = shift;
    my $collected_links_ref = shift;
    my $cur_vimwiki_file = shift;
    my $cur_vimwiki_dir = dirname $cur_vimwiki_file;

    my @links = $line =~ m/$link_regexp/g;
    foreach (@links) {
        my $link_file = "";
        my $link_des = "";
        if (index($_, "|") >= 0) {
            $link_file = s/\|.*//r;
            $link_des = s/.*\|//r;
        } else {
            $link_file = $_;
        }
        unless (length $link_file) {next;}

        # convert link format to org type
        # such as '[[folder/file|des]]' -> '[[file][des]]'
        my $org_link_name = basename $link_file;
        if (length $link_des) {
            $line =~ s/\[\[\Q$_\E\]\]/\[\[$org_link_name\]\[$link_des\]\]/g;
        } else {
            $line =~ s/\[\[\Q$_\E\]\]/\[\[$org_link_name\]\]/g;
        }

        # collect the link file's complete path
        $link_file .= $vimwiki_ext;
        $link_file = &build_path($cur_vimwiki_dir, $link_file);
        if(not @$collected_links_ref ~~ /^\Q$link_file\E$/) {
            push @$collected_links_ref , $link_file;
        }
    }
    $line;
}

# expand collected links in current org headline
# before start a new org headline
sub expand_collected_links {
    my $collected_links_ref = shift;
    my $org_parent_lv = shift;

    say $org_parent_lv;
    # open_and_dispatch($_, $org_parent_lv) foreach (@$collected_links_ref);
    say foreach (@$collected_links_ref);

    # empty collected links
    @$collected_links_ref = ();
}

# TODO
sub help {
    # how to check log
}
