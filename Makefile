PREFIX ?= /usr
OPTDIR ?= /opt/makeapex
DESTDIR ?=

.PHONY: all install uninstall

all:
	@echo "Nothing to build for makeapex. Run 'make install' to install."

install:
	install -d $(DESTDIR)$(OPTDIR)
	install -d $(DESTDIR)$(PREFIX)/bin
	cp -r src/* $(DESTDIR)$(OPTDIR)/
	chmod +x $(DESTDIR)$(OPTDIR)/makeapex.sh
	ln -sf $(OPTDIR)/makeapex.sh $(DESTDIR)$(PREFIX)/bin/makeapex

uninstall:
	rm -rf $(DESTDIR)$(OPTDIR)
	rm -f $(DESTDIR)$(PREFIX)/bin/makeapex
