#!/bin/sh
# Bundle a built git binary into a release tarball: the binary itself,
# upstream COPYING (unmodified, from the verified source tree), and a
# generated BUILD.md documenting exactly how it was built.
#
# Usage: package-release.sh <git-version> <arch> <src-dir> <git-binary> <output-dir>
#   git-version  e.g. 2.55.0
#   arch         e.g. amd64 | arm64
#   src-dir      verified upstream source tree (must contain COPYING)
#   git-binary   path to the built, smoketest-passed static git binary
#   output-dir   where to write the tarball + checksum
set -eu

GIT_VERSION="${1:?usage: package-release.sh <git-version> <arch> <src-dir> <git-binary> <output-dir>}"
ARCH="${2:?usage: package-release.sh <git-version> <arch> <src-dir> <git-binary> <output-dir>}"
SRC_DIR="${3:?usage: package-release.sh <git-version> <arch> <src-dir> <git-binary> <output-dir>}"
GIT_BIN="${4:?usage: package-release.sh <git-version> <arch> <src-dir> <git-binary> <output-dir>}"
OUT_DIR="${5:?usage: package-release.sh <git-version> <arch> <src-dir> <git-binary> <output-dir>}"

BASE_IMAGE_DIGEST="${BASE_IMAGE_DIGEST:-unknown}"
BUILD_FLAGS="${BUILD_FLAGS:-CFLAGS=-static LDFLAGS=\"-static -s\" NO_OPENSSL=1 NO_CURL=1 NO_EXPAT=1 NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_GETTEXT=1 NO_ICONV=1 NO_REGEX=NeedsStartEnd NO_RUST=1}"

[ -f "${SRC_DIR}/COPYING" ] || {
    echo "FATAL: ${SRC_DIR}/COPYING not found" >&2
    exit 1
}
[ -x "${GIT_BIN}" ] || {
    echo "FATAL: ${GIT_BIN} not found or not executable" >&2
    exit 1
}

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

STAGE="${WORK_DIR}/git-${GIT_VERSION}-linux-${ARCH}"
mkdir -p "$STAGE"

cp "${GIT_BIN}" "${STAGE}/git"
chmod 755 "${STAGE}/git"
cp "${SRC_DIR}/COPYING" "${STAGE}/COPYING"

cat > "${STAGE}/BUILD.md" <<EOF
# git ${GIT_VERSION} - linux/${ARCH} static build

- Upstream version: ${GIT_VERSION}
- Target: linux/${ARCH}, statically linked against musl libc
- Base image: ${BASE_IMAGE_DIGEST}
- Build flags: ${BUILD_FLAGS}
- Source: verified against the upstream release signature before building
  (see keys/junio-hamano.asc in the gitcloud-git-static repository)
- License: git itself is GPL-2.0-only, unmodified upstream; see COPYING in
  this archive. The build tooling that produced this archive
  (gitcloud-git-static) is licensed separately, under AGPL-3.0-or-later.
- Scope: this binary was smoke-tested against only the command set GitCloud
  needs (init, add, commit -m, checkout <hash> -- <path>,
  status --porcelain -z, config --get/--set, rev-parse HEAD, log). No
  network transports, hooks, submodules, or LFS were exercised or are
  guaranteed to work.
EOF

TARBALL="git-${GIT_VERSION}-linux-${ARCH}.tar.gz"
( cd "$WORK_DIR" && tar -czf "${OUT_DIR}/${TARBALL}" "git-${GIT_VERSION}-linux-${ARCH}" )

( cd "$OUT_DIR" && sha256sum "${TARBALL}" > "${TARBALL}.sha256" )

echo "==> Wrote ${OUT_DIR}/${TARBALL} and ${OUT_DIR}/${TARBALL}.sha256"
