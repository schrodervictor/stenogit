PREFIX    ?= /usr/local
DESTDIR   ?=
CONTAINER ?= podman
IMAGE     ?= config-tracker-test

BINDIR   := $(PREFIX)/bin
UNITDIR  := $(PREFIX)/lib/systemd/user
SHAREDIR := $(PREFIX)/share/config-tracker

BUILD_DIR := build

UNIT_TEMPLATES := \
    systemd/config-tracker@.service.in \
    systemd/config-tracker-watch@.service.in
UNIT_RENDERED := \
    $(BUILD_DIR)/systemd/config-tracker@.service \
    $(BUILD_DIR)/systemd/config-tracker-watch@.service
UNIT_PLAIN := \
    systemd/config-tracker@.timer
UNIT_COPIED := \
    $(BUILD_DIR)/systemd/config-tracker@.timer

BUILT_UNITS := $(UNIT_RENDERED) $(UNIT_COPIED)

SCRIPTS := \
    bin/config-tracker \
    bin/config-tracker-commit \
    bin/config-tracker-watch

.PHONY: all build test image install uninstall clean

all: build

build: $(BUILT_UNITS)

$(BUILD_DIR)/systemd/%.service: systemd/%.service.in
	@mkdir -p $(@D)
	sed -e 's|@BINDIR@|$(BINDIR)|g' $< > $@

$(BUILD_DIR)/systemd/%.timer: systemd/%.timer
	@mkdir -p $(@D)
	cp $< $@

image:
	$(CONTAINER) build -t $(IMAGE) .

test: image
	$(CONTAINER) run --rm -v $(CURDIR):/src -w /src $(IMAGE) bats tests/

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(SCRIPTS) $(DESTDIR)$(BINDIR)/
	install -d $(DESTDIR)$(UNITDIR)
	install -m 0644 $(BUILT_UNITS) $(DESTDIR)$(UNITDIR)/
	install -d $(DESTDIR)$(SHAREDIR)
	install -m 0644 examples/example.conf $(DESTDIR)$(SHAREDIR)/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/config-tracker
	rm -f $(DESTDIR)$(BINDIR)/config-tracker-commit
	rm -f $(DESTDIR)$(BINDIR)/config-tracker-watch
	rm -f $(DESTDIR)$(UNITDIR)/config-tracker@.service
	rm -f $(DESTDIR)$(UNITDIR)/config-tracker@.timer
	rm -f $(DESTDIR)$(UNITDIR)/config-tracker-watch@.service
	rm -f $(DESTDIR)$(SHAREDIR)/example.conf

clean:
	rm -rf $(BUILD_DIR)
