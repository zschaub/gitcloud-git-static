#!/bin/sh
# Fetch a git release tarball from kernel.org, verify its detached PGP
# signature against the pinned key in keys/junio-hamano.asc, and extract it.
#
# Usage: verify-source.sh <git-version> <output-src-dir>
#
# Fails (and leaves no extracted source behind) on any download, signature,
# or verification-command failure. Never build from an unverified tarball.
set -eu

GIT_VERSION="${1:?usage: verify-source.sh <git-version> <output-src-dir>}"
OUT_DIR="${2:?usage: verify-source.sh <git-version> <output-src-dir>}"
KEY_FILE="${KEY_FILE:-/keys/junio-hamano.asc}"
MIRROR="${GIT_MIRROR:-https://mirrors.edge.kernel.org/pub/software/scm/git}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL="git-${GIT_VERSION}.tar.xz"
SIGFILE="git-${GIT_VERSION}.tar.sign"

echo "==> Downloading ${TARBALL} and ${SIGFILE} from ${MIRROR}"
curl -fsSL -o "${WORK_DIR}/${TARBALL}" "${MIRROR}/${TARBALL}"
curl -fsSL -o "${WORK_DIR}/${SIGFILE}" "${MIRROR}/${SIGFILE}"

echo "==> Decompressing ${TARBALL} (the upstream signature covers the raw .tar, not .tar.xz)"
unxz -k "${WORK_DIR}/${TARBALL}"
RAW_TAR="${WORK_DIR}/git-${GIT_VERSION}.tar"

echo "==> Verifying signature against pinned key ${KEY_FILE}"
export GNUPGHOME="${WORK_DIR}/gnupg"
mkdir -m 700 "${GNUPGHOME}"
gpg --batch --import "${KEY_FILE}"

# gpg --status-fd lets us assert on GOODSIG rather than trusting exit code +
# human-readable text alone.
STATUS_FILE="${WORK_DIR}/gpg-status"
gpg --batch --status-fd 1 --verify "${WORK_DIR}/${SIGFILE}" "${RAW_TAR}" >"${STATUS_FILE}" 2>&1 || {
    echo "FATAL: signature verification failed for git-${GIT_VERSION}.tar" >&2
    cat "${STATUS_FILE}" >&2
    exit 1
}
grep -q '^\[GNUPG:\] GOODSIG ' "${STATUS_FILE}" || {
    echo "FATAL: no GOODSIG status from gpg for git-${GIT_VERSION}.tar" >&2
    cat "${STATUS_FILE}" >&2
    exit 1
}
echo "==> Signature OK"

mkdir -p "${OUT_DIR}"
tar -xf "${RAW_TAR}" -C "${OUT_DIR}" --strip-components=1

echo "==> Extracted verified source to ${OUT_DIR}"
