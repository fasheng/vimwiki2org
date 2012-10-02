#! /usr/bin/awk -f

#BEGIN {
    #file = "test.wiki"
    ##while ((getline line < file) > 0)
        ##print line
    #while ((getline < file) > 0)
        #print $0
    #close(file)
#}

BEGIN {

    # define arrary to collect links in vimwiki
    links[1] = ""

    # add org file tags
    # TODO, variable
    file_tags = "vimwiki"
    print "#+FILETAGS: :" file_tags ":"

    #source = "=== title ==="
    #target = gensub(/^=+ (.*) =+$/, "\\1", "g", source)
    #print source
    #print target

    #n = 1
    #test(n)
    #print n
}

function test(i) {
    i++
}

# commit and placeholder of vimwiki, which all start with "%"
# such as "%title", "%% commit"
/^\s*%/ {
    print "# " $0
    next
}

# headers in vimwiki
# such as "=== header ==="
/^=+.*=+$/ {
    # header prefix, such as "=="
    hp = gensub(/^(=+) .*$/, "\\1", "g")

    # header level, i.e., the count of "="
    hl = length(hp)

    # the first header level of the current file
    # for not all file's first header is level one, so we select
    # the first one as a opposing start level, and could be used to
    # compute other header's org level in same file
    # for example, the first header level in a vimwiki file is 3,
    # "=== header ===", if not think of its parent level, it will be
    # convert to a org header as level 1, "* header"
    fhl = hl

    # org parent header level
    org_phl = 0

    # comput org header level
    org_hl = hl - fhl
    if (org_hl < 0) org_hl = 0;
    org_hl += org_phl + 1;

    # get header text, remove "=" in the header line
    #sub(/^=+ /, "")
    #sub(/ =+$/, "")
    org_ht = gensub(/^=+ (.*) =+$/, "\\1", "g")

    print get_org_hl(org_hl, org_ht)

    # mark enter a header now
    under_header = 1
    # TODO
    list_first_pre_spc_num = -1

    # the header line is easy to dispatch, just move to next line
    next
}

# lists in vimwiki
# such as "* list", "- list", "# list"
/^\s*[#*-] / {
    # TODO use match
    list_pre_spc = gensub(/^(\s*).*$/, "\\1", "g")
    list_pre_spc_num = length(list_pre_spc)
    #print "t: " list_pre_spc
    #print "t: " list_pre_spc_num
    if (list_first_pre_spc_num < 0)
        list_first_pre_spc_num = list_pre_spc_num

# TODO get list text
    org_lt = gensub(/^\s*[#*-] (.*)$/, "\\1", "g")

# TODO comput list header level
    if(list_pre_spc_num <= list_first_pre_spc_num) {
        if(under_header)
            org_ll = org_hl + 1
        else
            org_ll = org_phl + 1
    } else {
        org_ll = 0
    }

    if (org_ll > 0)
        print get_org_hl(org_ll, org_lt)
    else
        print
}

#{
    #file = "test.wiki"
    #while ((getline line < file) > 0)
        #print line
    #while ((getline < file) > 0)
        #print NR, NF, $0
    #close(file)
#}

# build org header line, such as "*** header"
function get_org_hl(org_hl, org_ht,    i) {
# TODO
#function org_hl(hl, fhl, org_phl, org_ht,    i) {
    #hl = hl - fhl
    #if (hl < 0) hl = 0;
    #hl += org_phl + 1;

    # org header prefix
    org_hp = ""
    for (i=1; i<=org_hl; i++)
        org_hp = org_hp "*"

    return org_hp " " org_ht
}

function collect_links(    i,l) {

    }

function dispatch_links(    i,l) {

    }

function empty_links(    i,l) {
    l=length(a)
    for(i=2; i<=l; i++)
        delete links[i]
}
