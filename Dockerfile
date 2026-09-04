# syntax=docker/dockerfile:1.7
#
# Multi-stage build of a minimal, statically-linked (musl) git binary,
# scoped to exactly what GitCloud needs. See AGENTS.md for the command
# surface and rationale.
#
# Stages: source -> build -> smoketest -> export
#   - source:    download + GPG-verify the upstream release tarball, extract it.
#   - build:     compile a static git against musl with unneeded features
#                (network transports, perl, tcl/tk, gettext, iconv...) compiled out.
#   - smoketest: prove the binary works, in a container with NO system git,
#                by running the exact GitCloud command sequence.
#   - export:    the smoketest-verified binary only, for `--output type=local`.

ARG ALPINE_VERSION=3.20
ARG GIT_VERSION=2.55.0

# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS source

RUN apk add --no-cache curl gnupg xz tar

COPY keys/junio-hamano.asc /keys/junio-hamano.asc
COPY scripts/verify-source.sh /usr/local/bin/verify-source.sh
RUN chmod +x /usr/local/bin/verify-source.sh

ARG GIT_VERSION
ENV KEY_FILE=/keys/junio-hamano.asc
RUN verify-source.sh "${GIT_VERSION}" /src

# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS build

# build-base pulls in gcc/musl-dev/make. zlib-static is required for a true
# static link (zlib-dev alone only ships the shared lib on Alpine).
RUN apk add --no-cache build-base zlib-dev zlib-static linux-headers file

COPY --from=source /src /src
WORKDIR /src

# Flag set confirmed empirically against Alpine/musl (see BUILD.md emitted
# per release for the exact set used in that build):
#   NO_OPENSSL / NO_CURL / NO_EXPAT - no network transports (GitCloud is local-only).
#   NO_PERL / NO_PYTHON / NO_TCLTK  - no git-svn, git-send-email, gitk, git-gui.
#   NO_GETTEXT / NO_ICONV           - no message translation; musl's iconv is a
#                                      stub anyway and pulling it in risks a
#                                      dynamic dependency we don't need.
#   NO_REGEX=NeedsStartEnd          - musl's regex lacks REG_STARTEND; without
#                                      this the build fails outright (empirically
#                                      confirmed, not optional on musl).
#   NO_RUST                         - git is growing an optional Rust component
#                                      (git 2.55+); building it needs cargo, which
#                                      we don't install. Upstream states Rust
#                                      becomes mandatory in git 3.0, at which
#                                      point this flag and this comment go away.
# CFLAGS/LDFLAGS=-static (not -static-pie) to get a true static binary rather
# than a static-PIE, which would still carry a dynamic loader dependency.
# LDFLAGS also strips (-s) to shrink the binary; smoketest re-verifies the
# result is truly static regardless of these flags succeeding as intended.
RUN make -j"$(nproc)" \
        CFLAGS="-static" \
        LDFLAGS="-static -s" \
        NO_OPENSSL=1 \
        NO_CURL=1 \
        NO_EXPAT=1 \
        NO_PERL=1 \
        NO_PYTHON=1 \
        NO_TCLTK=1 \
        NO_GETTEXT=1 \
        NO_ICONV=1 \
        NO_REGEX=NeedsStartEnd \
        NO_RUST=1 \
        prefix=/dist \
        install

# Fail the build outright if the result isn't truly static (e.g. static-PIE).
# On musl, `ldd` against a non-dynamic binary refuses to run it ("Not a
# valid dynamic program") rather than printing glibc's "not a dynamic
# executable" message - either phrasing proves there's no dynamic loader
# dependency, which is what we're actually checking for.
RUN file /dist/bin/git && \
    file /dist/bin/git | grep -qi 'statically linked' && \
    { ldd /dist/bin/git 2>&1 | grep -qiE 'not a dynamic|not a valid dynamic'; }

# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS smoketest

# No `git` package installed here: any hidden dynamic dependency or PATH
# fallback to a system git would otherwise mask a real gap.
RUN apk add --no-cache file

COPY --from=build /dist/bin/git /git-bin/git
COPY scripts/smoketest.sh /usr/local/bin/smoketest.sh
RUN chmod +x /usr/local/bin/smoketest.sh

RUN smoketest.sh /git-bin/git

# ---------------------------------------------------------------------------
FROM scratch AS export

COPY --from=smoketest /git-bin/git /git
