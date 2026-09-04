# Standalone smoketest image, independent of the main multi-stage
# Dockerfile. Used to re-verify an already-packaged release binary (e.g.
# extracted from a release tarball into ./dist/git) with no dependency on
# the build pipeline that produced it - proves the exact bytes being shipped
# work, not just an intermediate copy.
#
# Build from the repo root with the binary staged at ./dist/git:
#   docker build -f smoketest/Dockerfile -t gitcloud-git-static-smoketest .
FROM alpine:3.20

# No `git` package installed: any hidden dynamic dependency or PATH
# fallback to a system git would otherwise mask a real gap.
RUN apk add --no-cache file

COPY scripts/smoketest.sh /usr/local/bin/smoketest.sh
RUN chmod +x /usr/local/bin/smoketest.sh

COPY --chmod=755 dist/git /git-bin/git

ENTRYPOINT ["smoketest.sh"]
CMD ["/git-bin/git"]
