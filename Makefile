### Makefile ---
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License as
## published by the Free Software Foundation; either version 3, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; see the file COPYING.  If not, write to
## the Free Software Foundation, Inc., 51 Franklin Street, Fifth
## Floor, Boston, MA 02110-1301, USA.
##
######################################################################
##
### Code:

DESTDIR=
prefix=$(DESTDIR)/usr/local
exec_prefix=$(prefix)
bindir=$(exec_prefix)/bin
datarootdir=$(prefix)/share
datadir=$(datarootdir)
appname=vimwiki2org
pkgdatadir=$(datadir)/$(appname)

.PHONY : help install uninstall
all : help
help :
	@echo "Usage:"
	@echo "    make [install|uninstall|help] [DESTDIR=\"$(DESTDIR)\"] [prefix=\"$(prefix)\"]"

datafiles=Makefile README.markdown
install :
	@echo "==> install..."
	mkdir -p $(pkgdatadir)
	install -m644 $(datafiles) $(pkgdatadir)/
	cp -rf example $(pkgdatadir)/
	mkdir -p $(bindir)
	install -m755 vimwiki2org.pl $(bindir)/vimwiki2org
	@echo "==> done."

uninstall :
	@echo "==> uninstall..."
	rm -rf $(pkgdatadir)
	rm -f $(bindir)/vimwiki2org
	@echo "==> done."

######################################################################
### Makefile ends here
