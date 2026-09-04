#!/bin/sh
# Exercises the exact git command sequence GitCloud depends on, against a
# single binary, inside an environment with no system git installed.
#
# Usage: smoketest.sh <path-to-git-binary>
#
# Must be run with stdin from /dev/null and $EDITOR/$VISUAL unset (or
# pointed at something that fails), so that `commit -m` provably never
# opens an editor. Exits nonzero on the first failure.
set -eu

GIT="${1:?usage: smoketest.sh <path-to-git-binary>}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

unset EDITOR
unset VISUAL
export GIT_EDITOR=false

fail() {
    echo "SMOKETEST FAILED: $*" >&2
    exit 1
}

echo "==> Using binary: ${GIT}"
"$GIT" --version </dev/null || fail "git --version"

echo "==> file/ldd sanity"
file "$GIT" || true
# glibc's ldd prints "not a dynamic executable"; musl's refuses to run the
# binary at all ("Not a valid dynamic program"). Either phrasing proves
# there's no dynamic loader dependency, which is what we're checking for.
if command -v ldd >/dev/null 2>&1; then
    LDD_OUT="$(ldd "$GIT" 2>&1 || true)"
    echo "$LDD_OUT"
    echo "$LDD_OUT" | grep -qiE 'not a dynamic|not a valid dynamic' || \
        fail "binary does not appear to be statically linked"
fi

echo "==> git init"
"$GIT" init . </dev/null || fail "init"

echo "==> git config --local user.name / user.email (config --set path)"
"$GIT" config --local user.name "GitCloud Smoketest" </dev/null || fail "config --local user.name"
"$GIT" config --local user.email "smoketest@gitcloud.invalid" </dev/null || fail "config --local user.email"

echo "==> git config --get user.name"
NAME="$("$GIT" config --get user.name </dev/null)" || fail "config --get user.name"
[ "$NAME" = "GitCloud Smoketest" ] || fail "config --get user.name returned unexpected value: ${NAME}"

echo "==> git add"
echo "hello from gitcloud" > file.txt
"$GIT" add file.txt </dev/null || fail "add"

echo "==> git commit -m (must never touch \$EDITOR)"
"$GIT" commit -m "initial commit" </dev/null || fail "commit -m"

echo "==> git rev-parse HEAD"
FIRST_HASH="$("$GIT" rev-parse HEAD </dev/null)" || fail "rev-parse HEAD"
[ -n "$FIRST_HASH" ] || fail "rev-parse HEAD returned empty output"

echo "==> modify tracked file, git status --porcelain -z"
echo "modified" > file.txt
STATUS_OUT="$("$GIT" status --porcelain -z </dev/null)" || fail "status --porcelain -z"
case "$STATUS_OUT" in
    " M file.txt"*) : ;;
    *) fail "unexpected status --porcelain -z output: ${STATUS_OUT}" ;;
esac

echo "==> git checkout <hash> -- <path> (rollback)"
"$GIT" checkout "$FIRST_HASH" -- file.txt </dev/null || fail "checkout <hash> -- <path>"
CONTENT="$(cat file.txt)"
[ "$CONTENT" = "hello from gitcloud" ] || fail "checkout did not restore original content, got: ${CONTENT}"

echo "==> git log"
"$GIT" log </dev/null | grep -q "initial commit" || fail "log did not contain expected commit message"

echo "==> SMOKETEST PASSED"
