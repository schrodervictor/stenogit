PREFIX    ?= /usr/local
DESTDIR   ?=
CONTAINER ?= podman
IMAGE     ?= stenogit-test

BINDIR   := $(PREFIX)/bin
UNITDIR  := $(PREFIX)/lib/systemd/user
SHAREDIR := $(PREFIX)/share/stenogit

BUILD_DIR := build

UNIT_TEMPLATES := \
    systemd/stenogit@.service.in \
    systemd/stenogit-watch@.service.in
UNIT_RENDERED := \
    $(BUILD_DIR)/systemd/stenogit@.service \
    $(BUILD_DIR)/systemd/stenogit-watch@.service
UNIT_PLAIN := \
    systemd/stenogit@.timer
UNIT_COPIED := \
    $(BUILD_DIR)/systemd/stenogit@.timer

BUILT_UNITS := $(UNIT_RENDERED) $(UNIT_COPIED)

SCRIPTS := \
    bin/stenogit \
    bin/stenogit-commit \
    bin/stenogit-watch

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
	rm -f $(DESTDIR)$(BINDIR)/stenogit
	rm -f $(DESTDIR)$(BINDIR)/stenogit-commit
	rm -f $(DESTDIR)$(BINDIR)/stenogit-watch
	rm -f $(DESTDIR)$(UNITDIR)/stenogit@.service
	rm -f $(DESTDIR)$(UNITDIR)/stenogit@.timer
	rm -f $(DESTDIR)$(UNITDIR)/stenogit-watch@.service
	rm -f $(DESTDIR)$(SHAREDIR)/example.conf

clean:
	rm -rf $(BUILD_DIR)
