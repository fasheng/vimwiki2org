## description

vimwiki2org.pl is a simple tool to convert vimwiki file to emacs
org-mode file

## usage

    vimwiki2org.pl index.wiki [file ...]
    vimwiki2org.pl [options] -- index.wiki [file ...]

## examples

- **print help message**

        vimwiki2org.pl --help

- **show man page**

        vimwiki2org.pl --man

- **convert the example vimwikie files to a org-mode file**

        vimwiki2org.pl /usr/share/vimwiki2org/example/index.wiki > vimwiki.org

- **convert vimwikie files, give the diary index file's relative path,
    and will check and append the lonely files in the same folder or sub
    folders with the main index file**

        vimwiki2org.pl -d diary/diary.wiki -L fix -- index.wiki > vimwiki.org

## install and uninstall

- **depends**
  - perl 5.14
- **compatibility**
  - test ok on vimwiki 2.0.1.stu
- **install**

        make install

- **uninstall**

        make uninstall

## binary files
- **/usr/bin/vimwiki2org**

  a wrapper to run the main script vimwiki2org.pl
