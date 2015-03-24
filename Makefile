PREFIX ?= /usr/local

sbindir := $(DESTDIR)/$(PREFIX)/sbin

narwhal.sh:

install:
	install -d -- '$(sbindir)'
	install -- narwhal.sh '$(sbindir)/narwhal'

.PHONY: install
