SHELL := /bin/bash
SCRIPTS := mkdistro bin/mkdistro $(wildcard steps/*.sh) $(wildcard presets/*/mkdistro.conf)

PREFIX ?= /usr/local
DESTDIR ?=
PRESET ?= presets/x86_64-qemu

.PHONY: lint lint-bash lint-shellcheck check install

lint: lint-bash lint-shellcheck

lint-bash:
	bash -n $(SCRIPTS)

lint-shellcheck:
	shellcheck $(SCRIPTS)

check:
	steps/validate.sh $(PRESET)

install:
	install -d -m0755 "$(DESTDIR)$(PREFIX)/share/mkdistro"
	install -m0755 mkdistro "$(DESTDIR)$(PREFIX)/share/mkdistro/mkdistro"
	cp -a steps common "$(DESTDIR)$(PREFIX)/share/mkdistro/"
	install -D -m0755 bin/mkdistro "$(DESTDIR)$(PREFIX)/bin/mkdistro"
