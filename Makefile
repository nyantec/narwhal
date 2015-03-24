PREFIX ?= /usr/local

sbindir := $(DESTDIR)/$(PREFIX)/sbin
man8dir := $(DESTDIR)/$(PREFIX)/share/man/man8

narwhal.sh:

install:
	install -d -- '$(sbindir)'
	install -m 755 -- narwhal.sh '$(sbindir)/narwhal'
	install -d -- '$(man8dir)'
	install -m 644 -- narwhal.8 '$(man8dir)'

.PHONY: install
