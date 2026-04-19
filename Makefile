PREFIX    ?= /usr/local
DESTDIR   ?=
CONTAINER ?= podman
IMAGE     ?= stenogit-test

BINDIR         := $(PREFIX)/bin
SYSTEM_UNITDIR := $(PREFIX)/lib/systemd/system
USER_UNITDIR   := $(PREFIX)/lib/systemd/user
SHAREDIR       := $(PREFIX)/share/stenogit

BUILD_DIR := build

SYSTEM_UNIT_TEMPLATES := \
    systemd/system/stenogit@.service.in \
    systemd/system/stenogit-watch@.service.in
SYSTEM_UNIT_RENDERED := \
    $(BUILD_DIR)/systemd/system/stenogit@.service \
    $(BUILD_DIR)/systemd/system/stenogit-watch@.service
SYSTEM_UNIT_PLAIN := \
    systemd/system/stenogit@.timer
SYSTEM_UNIT_COPIED := \
    $(BUILD_DIR)/systemd/system/stenogit@.timer

USER_UNIT_TEMPLATES := \
    systemd/user/stenogit@.service.in \
    systemd/user/stenogit-watch@.service.in
USER_UNIT_RENDERED := \
    $(BUILD_DIR)/systemd/user/stenogit@.service \
    $(BUILD_DIR)/systemd/user/stenogit-watch@.service
USER_UNIT_PLAIN := \
    systemd/user/stenogit@.timer
USER_UNIT_COPIED := \
    $(BUILD_DIR)/systemd/user/stenogit@.timer

SYSTEM_BUILT_UNITS := $(SYSTEM_UNIT_RENDERED) $(SYSTEM_UNIT_COPIED)
USER_BUILT_UNITS   := $(USER_UNIT_RENDERED) $(USER_UNIT_COPIED)
BUILT_UNITS        := $(SYSTEM_BUILT_UNITS) $(USER_BUILT_UNITS)

SCRIPTS := \
    bin/stenogit \
    bin/stenogit-commit \
    bin/stenogit-watch

.PHONY: all build test test-e2e lint image install uninstall clean

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
	$(CONTAINER) run --rm -v $(CURDIR):/src -w /src $(IMAGE) bats tests/unit/

# End-to-end tests against real systemd. Requires podman (not docker).
# Podman natively supports systemd containers: when it detects
# /lib/systemd/systemd as the entrypoint, it sets up tmpfs mounts,
# cgroups, and the stop signal automatically.
test-e2e: image
	@CID="$$(\
		podman container run \
			--detach \
			--volume $(CURDIR):/src \
			$(IMAGE) /lib/systemd/systemd \
	)"; \
	cleanup() { \
		podman container kill --signal SIGRTMIN+3 "$$CID" >/dev/null 2>&1; \
		podman container rm "$$CID" >/dev/null 2>&1; \
	}; \
	trap cleanup EXIT; \
	sleep 2; \
	podman exec "$$CID" bash -c " \
		make -C /src build install PREFIX=/usr BUILD_DIR=/tmp/stenogit-build \
		&& systemctl daemon-reload \
		&& bats /src/tests/e2e/ \
	"

lint: image
	$(CONTAINER) run --rm -v $(CURDIR):/src -w /src $(IMAGE) \
		shellcheck --shell=bash $(SCRIPTS) tests/unit/test_helper.bash

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(SCRIPTS) $(DESTDIR)$(BINDIR)/
	install -d $(DESTDIR)$(SYSTEM_UNITDIR)
	install -m 0644 $(SYSTEM_BUILT_UNITS) $(DESTDIR)$(SYSTEM_UNITDIR)/
	install -d $(DESTDIR)$(USER_UNITDIR)
	install -m 0644 $(USER_BUILT_UNITS) $(DESTDIR)$(USER_UNITDIR)/
	install -d $(DESTDIR)$(SHAREDIR)
	install -m 0644 examples/example.conf $(DESTDIR)$(SHAREDIR)/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/stenogit
	rm -f $(DESTDIR)$(BINDIR)/stenogit-commit
	rm -f $(DESTDIR)$(BINDIR)/stenogit-watch
	rm -f $(DESTDIR)$(SYSTEM_UNITDIR)/stenogit@.service
	rm -f $(DESTDIR)$(SYSTEM_UNITDIR)/stenogit@.timer
	rm -f $(DESTDIR)$(SYSTEM_UNITDIR)/stenogit-watch@.service
	rm -f $(DESTDIR)$(USER_UNITDIR)/stenogit@.service
	rm -f $(DESTDIR)$(USER_UNITDIR)/stenogit@.timer
	rm -f $(DESTDIR)$(USER_UNITDIR)/stenogit-watch@.service
	rm -f $(DESTDIR)$(SHAREDIR)/example.conf

clean:
	rm -rf $(BUILD_DIR)
