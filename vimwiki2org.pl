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
# This is a simple tool to convert vimwiki files to emacsorg-mode file,
# and the usage is simple:
# perl vimwiki2org.pl index.wiki > vimwiki.org
# perl vimwiki2org.pl -t tag1:tag2 -l log.txt -- index.wiki > vimwiki.org
#
# more options to see help
# perl vimwiki2org.pl --help
#
# more conversion rules to see man page
# perl vimwiki2org.pl --man
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
use Cwd 'abs_path';
use Getopt::Long;
use Pod::Usage;
use File::Find;

## global variables
my $program_name="vimwiki2org.pl";
my $version_msg = "$program_name version 0.1";

my @dispatched_files;
my @open_error_files;
my @lost_files;
my $org_comment = "#";

# links in vimwiki
# such as '[[file]] [[file|name]]'
my $link_regexp = '\[\[(.*?)\]\]';

# comment and placeholder of vimwiki, which all start with "%"
# such as "%title", "%% comment"
my $comment_regexp = '^\s*%';

# headers in vimwiki
# such as "=== header ==="
my $header_regexp = '^(?:\s*)(=+) *(.*\S) *\1(?:\s*)$';

# lists in vimwiki
# such as "* list", "- list", "# list"
my $list_regexp = '^(\s*)([#*-]) (.*)$';

# plain text in vimwiki
my $plain_regexp = '^(\s*)(.*)$';

# source(preformat) block in vimwiki
# such as '{{{', '{{{sh', '}}}'
my $src_block_begin_with_type_regexp = '^\s*{{{\s*\S+.*$';
my $src_block_begin_no_type_regexp = '^\s*{{{\s*$';
my $src_block_end_regexp = '^\s*}}}\s*$';

# other
my $log_fh;

# options
my $org_file_tags = "vimwiki";  # add org file tags
my $log_file = "/tmp/vimwiki2org.log";
my $vimwiki_ext = '.wiki';
my $ignore_lonely_header = 1;
my $untyped_preformat_block_convert_type = undef;
my $dispatch_lost_files = '';

## main loop
my $man = 0;
my $help = 0;
my $version = 0;
$Getopt::Long::ignorecase = 0;
GetOptions(
    'file-tags|t:s'       => \$org_file_tags,
    'no-file-tags|no-t'   => sub{ $org_file_tags='' },
    'log-file|l:s'        => \$log_file,
    'no-log-file|no-l:s'  => sub{ $log_file='' },
    'vimwiki-ext|e:s'     => \$vimwiki_ext,
    'lost-files|L:s'      => \$dispatch_lost_files,
    'ignore-lonely-header|i!' => \$ignore_lonely_header,
    'untyped-preformat-block-convert-type|u:s' => \$untyped_preformat_block_convert_type,
    'help|h'    => \$help,
    'man|m'     => \$man,
    'version|v' => \$version
) or pod2usage(1);
pod2usage(1) if $help;
pod2usage(-verbose => 2) if $man;
if ($version) {
    say $version_msg;
    exit;
}

&open_log();
if ($org_file_tags) {
    say $org_comment, '+FILETAGS: :', $org_file_tags, ":\n";
}
my $diary_index_file;
foreach (@ARGV) {
    # the vimwiki index file
    my $index_file = $_;
    $index_file = File::Spec->canonpath($index_file);

    # the vimwiki diary index file, this file will dispatched at end
    my $vimwiki_base_dir = dirname $index_file;
    $diary_index_file = &build_path($vimwiki_base_dir, "diary/diary.wiki");

    &open_and_dispatch($index_file);
    &open_and_dispatch($diary_index_file);
}
if ($dispatch_lost_files eq 'check') {
    &check_lost_files();
} elsif ($dispatch_lost_files eq 'fix') {
    &check_lost_files();
    &fix_lost_files();
}
&close_log();

sub build_path {
    my $path = File::Spec->catfile(@_);
    &clean_path($path);
}

sub clean_path {
    my $path = shift;
    # clean up path, remove "./"
    $path = File::Spec->canonpath($path);
    # clean up path, remove "../"
    if ($path =~ /\.\./) {
        my $abs_path = abs_path($path);
        if (defined $abs_path) {
            $path = File::Spec->abs2rel($abs_path);
        }
    }
    $path;
}

sub open_log {
    return unless $log_file;
    eval {open $log_fh, ">", $log_file};
    warn $@ if ($@);
    &append_log("# MESSAGES");
}

sub append_log {
    return unless defined $log_fh;
    my $msg = shift;
    say {$log_fh} $msg if (fileno $log_fh);
}

sub close_log {
    &append_log("\n# DISPATCHED FILES");
    &append_log($_) foreach (@dispatched_files);
    &append_log("\n# OPEN FAILED FILES");
    &append_log($_) foreach (@open_error_files);
    if ($dispatch_lost_files) {
        &append_log("\n# LOST FILES");
        &append_log($_) foreach (@lost_files);
    }
    eval {close $log_fh};
}

my @found_files;
sub check_lost_files {
    my @base_dir;
    push @base_dir, dirname $_ foreach @ARGV;
    @found_files = ();
    find(sub {push @found_files, $File::Find::name if /$vimwiki_ext$/;}, @base_dir);
    $_ = &clean_path($_) foreach @found_files;
    foreach (@found_files) {
        if (not @dispatched_files ~~ /^\Q$_\E$/) {
            push @lost_files, $_ if (not @lost_files ~~ /^\Q$_\E$/);
        }
    }
}

sub fix_lost_files {
    my $org_parent_lv = 0;
    {
        my $org_headline_text = "fixed lost files";
        my $org_headline_lv = $org_parent_lv + 1;
        say &build_org_headline($org_headline_text, $org_headline_lv);
        $org_parent_lv++;
    }
    open_and_dispatch($_, $org_parent_lv)  foreach @lost_files;
}

# main function
sub open_and_dispatch {
    my $vimwiki_file = shift;
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

    # convert filename as the main org headline first
    {
        my $org_headline_text = basename $vimwiki_file;
        $org_headline_text =~ s/\.[^.]+$//; # remove file extension name
        my $org_headline_lv = $org_parent_lv + 1;
        say &build_org_headline($org_headline_text, $org_headline_lv);

        $org_parent_lv++;
    }

    # count headers in vimwiki
    my $header_count = grep /$header_regexp/, @content;

    # find the minimum header level in current file, and set it as
    # the start org level, for example, the minimus header level is 3,
    # like "=== header ===", if not think of its parent level, it will be
    # convert to a org header as level 1, like "* header"
    my @headers = grep /$header_regexp/, @content;
    my $min_header_lv = 0;
    if (@headers) {
        $min_header_lv = length((shift @headers) =~ s/$header_regexp/$1/r);
        foreach (@headers) {
            my $header_lv = length(s/$header_regexp/$1/r);
            if ($header_lv < $min_header_lv) {
                $min_header_lv = $header_lv;
            }
        }
    }

    ## dispatch the content

    # links under current org headline
    my @collected_links = ();
    my $last_org_headline_lv = $org_parent_lv;

    my $org_parent_lv_for_following_list = $org_parent_lv;
    # remember the first list item's prefix space count in a header
    # use this to judge if a list is first level under the header
    my $first_list_pre_spc_count = undef;

    # a marker to dispatch source code, select is is "#+begin_src" or "#+begin_example"
    my $last_begin_as_src;
    my $under_src_block;

    foreach(@content) {
        # my $exist_link_in_cur_line = 0;
        given ($_) {
            # comment and placeholder of vimwiki, which all start with "%"
            when (/$comment_regexp/) {
                say "# ", $_;
            }

            # links in vimwiki
            when (/$link_regexp/) {
                continue if $under_src_block;
                $_ = &convert_link_format($_);
                continue;
            }

            # headers in vimwiki
            when (/$header_regexp/) {
                continue if $under_src_block;
                &expand_collected_links(\@collected_links, $last_org_headline_lv);

                # reset markers
                $first_list_pre_spc_count = undef;

                if ($ignore_lonely_header) {
                    # if there is only one header, ignore it
                    if ($header_count <= 1) {
                        say $org_comment, $_;
                        break;
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
                continue if $under_src_block;
                my $list_pre_spc_count = length(s/$list_regexp/$1/r);
                my $list_text = s/$list_regexp/$3/r;
                if (!defined($first_list_pre_spc_count)) {
                    $first_list_pre_spc_count = $list_pre_spc_count;
                }
                if ($list_pre_spc_count <= $first_list_pre_spc_count) {
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
                # convert source code:
                # '{{{' -> '#+begin_example', '{{{sh' -> '#+begin_src sh'
                # '{{{class="brush: sh"' -> '#+begin_src sh'
                if (/$src_block_begin_with_type_regexp/) {
                    # source code with type
                    if (/class=/) {
                        s/{{{.*:\s*(\S+)\s*"\s*$/#+begin_src $1/;
                    } else {
                        s/{{{\s*(\S+)\s*$/#+begin_src $1/;
                    }

                    $last_begin_as_src = 1;
                    $under_src_block = 1;
                } elsif (/$src_block_begin_no_type_regexp/) {
                    # source code without type
                    if (defined $untyped_preformat_block_convert_type) {
                        s/{{{\s*/#+begin_src $untyped_preformat_block_convert_type/;
                        $last_begin_as_src = 1;
                    } else {
                        s/{{{\s*/#+begin_example/;
                        $last_begin_as_src = 0;
                    }
                    $under_src_block = 1;
                } elsif (/$src_block_end_regexp/) {
                    if ($last_begin_as_src) {
                        s/}}}\s*/#+end_src/;
                    } else {
                        s/}}}\s*/#+end_example/;
                    }
                    $under_src_block = 0;
                }

                say;
            };
        }                       # given-when end

        # collect links in current line, and these links will be expand
        # before next org headline output, in another hand, they will
        # be append at the end of current org headline(if exist)
        &collect_links($_, \@collected_links, $vimwiki_file) if (!$under_src_block);
    }                           # foreach end

    # end of file, expand collected_links in last org headline
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

# convert link format to org type
sub convert_link_format {
    my $line = shift;
    my @links = $line =~ m/$link_regexp/g;
    foreach (@links) {
        my $link_content = "";
        my $link_des = "";
        if (index($_, "|") >= 0) {
            # exist description in vimwiki link, split it
            $link_content = s/\|.*//r;
            $link_des = s/.*\|//r;
        } else {
            # there is no description
            $link_content = $_;
        }
        if (!length $link_content) {next;}

        # convert link format to org type
        # such as '[[folder/file|des]]' -> '[[file][des]]'
        # or '[[http://url|des]]' -> '[[http://url][des]]'
        my $org_link_name;
        if ($link_content =~ m{.+://}) {
            # url link
            $org_link_name = $link_content;
        } else {
            # file link
            $org_link_name = basename $link_content;
        }
        if (length $link_des) {
            $line =~ s/\[\[\Q$_\E\]\]/\[\[$org_link_name\]\[$link_des\]\]/g;
        } else {
            $line =~ s/\[\[\Q$_\E\]\]/\[\[$org_link_name\]\]/g;
        }
    }
    $line;
}
# collect links under current org headline
sub collect_links {
    my $line = shift;
    my $collected_links_ref = shift;
    my $cur_vimwiki_file = shift;
    my $cur_vimwiki_dir = dirname $cur_vimwiki_file;

    my @links = $line =~ m/$link_regexp/g;
    foreach (@links) {
        my $link_content = "";
        my $link_des = "";
        if (index($_, "|") >= 0) {
            $link_content = s/\|.*//r;
            $link_des = s/.*\|//r;
        } else {
            $link_content = $_;
        }
        if (!length $link_content) {next;}
        if ($link_content =~ m{.+://}) {next;}

        # collect the link file's complete path
        $link_content .= $vimwiki_ext;
        $link_content = &build_path($cur_vimwiki_dir, $link_content);
        if(not @$collected_links_ref ~~ /^\Q$link_content\E$/) {
            push @$collected_links_ref, $link_content;
        }
    }
}

# expand collected links in current org headline
# before start a new org headline
sub expand_collected_links {
    my $collected_links_ref = shift;
    my $org_parent_lv = shift;

    foreach (@$collected_links_ref) {
        # not expand diary index file here, it will be dispatch at end
        if ($_ ne $diary_index_file) {
            open_and_dispatch($_, $org_parent_lv);
        } else {
            &append_log("find diary index file as a link: " . $_);
        }
    }

    # empty collected links
    @$collected_links_ref = ();
}

__END__

=head1 NAME

vimwiki2org.pl - a simple tool to convert vimwiki to emacs org-mode

=head1 SYNOPSIS

vimwiki2org.pl index.wiki [file ...]

vimwiki2org.pl [options] -- index.wiki [file ...]

=head1 OPTIONS

=over 8

=item B<-t>, B<--file-tags>=tag1:tag2, B<--no-t>, B<--no-file-tags>

set the org-mode's file tags(#+FILETAGS), if is empty or
use B<--no-file-tags> will not insert file tags
(B<default> value is: "vimwiki")

=item B<-l>, B<--log-file>=log.txt, B<--no-l>, B<--no-log-file>

set the log file, if is empty or use B<--no-log-file> will not write log,
the log file contain three sections:'MESSAGES', 'DISPATCHED FILES',
'OPEN FAILED FILES'
(B<default> value is: "/tmp/vimwiki2org.log")

=item B<-L>, B<--lost-files>=<B<check>|B<fix>>

set if check or fix the vimwiki files which is not dispatched and in the same
folder or sub folders with the file(s) in options, if use 'B<check>', will
append a new section named 'LOST FILES' in log file, if use 'B<fix>', will
append the lost files' content under level 1 headline named "lost files"
(B<default> value is: <none>)

=item B<-e>, B<--vimwiki-ext>=.wiki

set the default vimwiki's file extension name
(B<default> value is: ".wiki")

=item B<-i>, B<--ignore-lonely-header>, B<--no-i>, B<--no-ignore-lonely-header>

set if ignore the only one header in a vimwiki file, because we have
set its filename as a parent org-mode headline
(B<default> option is: B<--ignore-lonely-header>)

=item B<-u>, B<--untyped-preformat-block-convert-type>=perl

set the untyped preformat block's type after converting, vimwiki's preformat
block is code which in 'B<{{{...}}}>', some with a type such as
'B<{{{sh...>', another without a type such as 'B<{{{...>', default, a
typed preformat code will convert to as org source block, such as
'B<#+<begin_src sh>', an untyped preformat code will convert to as org
example block, such as 'B<#+begin_example>', if you use
B<--untyped-preformat-block-convert-type>, the untyped preformat block will
convert to as org source block with your defined type, too
(B<default> value is: <undef>)

=item B<-h>, B<--help>

print a brief help message and exits

=item B<-m>, B<--man>

prints the manual page and exits

=item B<-v>, B<--version>

prints the version information and exits

=back

=head1 DESCRIPTION

B<This program> will read the given input vimwiki file(s) and convert to
org-mode and output, here is the conversion rules:

=over 8

=item * B<comment> and B<placeholder> in vimwiki, which start with 'B<%>'

all will be treat as org-mode's comment line which start with 'B<#>',
B<for example>:

'B<%title>' =>'B<#%title>', 'B<%% comment>' => 'B<#%% comment>'

=item * B<headers> in vimwiki, which surround with 'B<=>'

will be treat as org-mode's headline, and the headline level should be compute
as followed steps:
first, if you enable option 'B<--ignore-lonely-header>'(default is enabled),
and there is only one header in the file, just ignore the header,
and comment the line, because a file always has a overall parent headline
which named as the file name, another overall parent headline is redundant;
second, find the minimum header level in file, and set it as
the start level, B<for example>, the minimus header level is 3,
if not think of its parent level, it will be
convert to a org headline as level 1,

'B<=== header ===>'  =>  'B<* header>'

=item * B<list> item in vimwiki, which start with 'B<->' 'B<*>' 'B<#>'

the first level list item under a org-mode headline, will be convert to
headline, just like header in vimwiki,
and the TODO tag will convert to org-mode's TODO state,
B<for example>:

'B<- list item>'      =>  'B<* list item>',

'B<* [ ] list item>'  =>  'B<* TODO list item>',

'B<# [X] list item>'  =>  'B<* DONE list item>'

the sub level list item will be convert to standard org-mode plain list,
which start with 'B<->',
B<for example>:

'B<- list item>'      =>  'B<- list item>'

'B<* [ ] list item>'  =>  'B<- [ ] list item>'

=item * B<links> in vimwiki, which surround with 'B<[[>' 'B<]]>'

links will be treated as two kinds: file link(link to other vimwiki file),
and url link(http://, https://, ftp:// and so on).
first, convert the links to org-mode format, B<for example>:

'B<[[path/file]]>'  =>  'B<[[file]]>'

'B<[[file|des]]>'   =>  'B<[[file][des]]>'

'B<[[http://url|des]]>'  =>  'B<[[http://url][des]]>'

then, collect all the file links under the current org-mode headline,
and before next headline, expand these links, for each file, if
not dispatched yet, and is not the diary index file, will be append as a child
headline, named with the file name

=item * B<preformat>(B<source>) block in vimwiki, which surround with 'B<{{{>' 'B<}}}>'

preformat block will be convert to example or source block in org-mode,
if the preformat block with a type, such as 'perl' or 'python', it will
convert to source block, if no, will convert to a example block, but if
you use the option 'B<--untyped-preformat-block-convert-type>', the
untyped preformat block will convert to source block with your defined type,
B<for example>:

'B<{{{...}}}>'  =>  'B<#+begin_example...#+end_example>'
'B<{{{perl...}}}>'  =>  'B<#+begin_src perl...#+end_src>'
'B<{{{class="brush: sh...}}}">'  =>  'B<#+begin_src sh...#+end_src>'

and all the text under the prefomat block will be treat as plain text

=item * B<plain> text in vimwiki

just output without change

=item * B<multiple> vimwiki files as options

each file will be append as a level 1 org-mode headline, named with the file name,
unless the later file is dispatched as a link in the earlier file

=item * B<diary> index file in vimwiki

each file in options should has a diary index file, default is 'B<diary/diary.wiki>' relative to the file's path, it will be dispatched after the file,
as a level 1 org-mode headline

=back

=head1 EXAMPLES

perl vimwiki2org.pl example/index.wiki > vimwiki.org

perl vimwiki2org.pl -t tag1:tag2 -l log.txt -L=check -- index.wiki > vimwiki.org

=head1 AUTHOR

Written by Xu FaSheng.

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 3, or
(at your option) any later version.

=cut
