PREFIX ?= /usr/local

sbindir := $(DESTDIR)/$(PREFIX)/sbin
man8dir := $(DESTDIR)/$(PREFIX)/share/man/man8

narwhal:

install: $(sbindir)/narwhal $(man8dir)/narwhal.8

$(sbindir)/narwhal: narwhal $(sbindir)
	install -m 755 -t $(@D) $(@F)

$(man8dir)/narwhal.8: narwhal.8 $(man8dir)
	install -m 644 -t $(@D) $(@F)

$(sbindir) $(man8dir):
	install -d $@

.PHONY: install
