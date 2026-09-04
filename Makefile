# Thin local dev wrapper around buildx + scripts. CI (.github/workflows/)
# does not use this file - it runs the equivalent buildx/script commands
# directly so its steps are independently inspectable and cacheable.

GIT_VERSION ?= $(shell cat VERSION)
PLATFORMS   ?= linux/amd64,linux/arm64
DIST_DIR    ?= dist

.PHONY: build build-amd64 build-arm64 smoketest package clean

## Build + smoketest both architectures, export binaries to
## ./dist/linux_<arch>/git (buildx's local-output naming for multi-platform)
build:
	docker buildx build \
		--build-arg GIT_VERSION=$(GIT_VERSION) \
		--platform $(PLATFORMS) \
		--target export \
		--output type=local,dest=$(DIST_DIR) \
		.

build-amd64:
	$(MAKE) build PLATFORMS=linux/amd64

build-arm64:
	$(MAKE) build PLATFORMS=linux/arm64

## Re-run the standalone smoketest image against an already-built binary,
## without touching DIST_DIR. Usage: make smoketest ARCH=amd64
smoketest:
	@ctx=$$(mktemp -d); \
	mkdir -p "$$ctx/dist" "$$ctx/scripts"; \
	cp $(DIST_DIR)/linux_$(ARCH)/git "$$ctx/dist/git"; \
	cp scripts/smoketest.sh "$$ctx/scripts/smoketest.sh"; \
	docker build -f smoketest/Dockerfile -t gitcloud-git-static-smoketest "$$ctx"; \
	rm -rf "$$ctx"
	docker run --rm gitcloud-git-static-smoketest

## Package a built binary (see build-amd64/build-arm64) into a release tarball.
## Usage: make package ARCH=amd64 SRC_DIR=/path/to/verified/git/source
package:
	./scripts/package-release.sh \
		$(GIT_VERSION) $(ARCH) $(SRC_DIR) $(DIST_DIR)/linux_$(ARCH)/git $(DIST_DIR)/release

clean:
	rm -rf $(DIST_DIR)
