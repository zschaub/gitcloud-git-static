# gitcloud-git-static

Minimal, statically-linked (musl), GPG-verified `git` binaries for
linux/amd64 and linux/arm64, published as checksummed GitHub Release
assets. Built for exactly one consumer: the
[GitCloud](https://github.com/zschaub/gitcloud) Nextcloud app, which needs
to bundle a working `git` executable for environments where installing
`git` isn't possible - chiefly Nextcloud AIO, whose container filesystem is
replaced on every update, and eventually a one-click App Store install with
no shell access assumed at all.

This is not a general-purpose "portable git" project. See
[AGENTS.md](AGENTS.md) for the full scope rationale.

## What's supported

Only the command set GitCloud actually uses is built, smoke-tested, and
supported:

```
git init
git config --local user.name / user.email   (config --set path)
git config --get user.name
git add <path>
git commit -m "..."                          (never opens $EDITOR)
git rev-parse HEAD
git checkout <hash> -- <path>
git status --porcelain -z
git log
```

No hooks, templates, submodules, LFS, or credential helpers are configured
or tested. No network transport (http/https/ssh) is available - `NO_CURL`
is set at build time, and no `ssh` binary is bundled - since GitCloud never
clones, fetches, pushes, or pulls.

`git init` prints a harmless `warning: templates not found in
/dist/share/git-core/templates` - that path is baked in from the build
environment and never exists at runtime, since only the bare `git` binary
is shipped (no `libexec/git-core` tree). It doesn't affect `init`'s exit
code or repository contents. For the same reason, `git commit` may print
`error: cannot run maintenance: No such file or directory` to stderr;
background auto-maintenance isn't part of GitCloud's command set and the
commit itself still succeeds.

## Installation

Download the tarball for your architecture from the
[Releases](../../releases) page, verify its checksum, and extract it:

```sh
curl -LO https://github.com/<org>/gitcloud-git-static/releases/download/vX.Y.Z-N/git-X.Y.Z-linux-amd64.tar.gz
curl -LO https://github.com/<org>/gitcloud-git-static/releases/download/vX.Y.Z-N/git-X.Y.Z-linux-amd64.tar.gz.sha256
sha256sum -c git-X.Y.Z-linux-amd64.tar.gz.sha256
tar xzf git-X.Y.Z-linux-amd64.tar.gz
```

Each tarball (`git-<version>-linux-<arch>.tar.gz`) contains:

- `git` - the static binary
- `COPYING` - upstream git's license, unmodified
- `BUILD.md` - exact upstream version, build flags, and base image digest
  used for that specific build

## Versioning

Releases are tagged `v<git_version>-<build_rev>` (e.g. `v2.55.0-1`).
`build_rev` lets the build recipe in this repo be revised and re-released
against the same upstream git version without needing a new upstream
release. Release builds are triggered manually via `workflow_dispatch`
(`.github/workflows/release.yml`) - not automatically off upstream tags -
so every published binary is a deliberate, reviewed build.

`VERSION` at the repo root pins the git version used by CI's fast
build+smoketest checks on every push/PR; it's independent of what gets
released and is bumped deliberately.

## Building locally

Requires Docker with `buildx`.

```sh
make build                 # both arches -> dist/linux_<amd64|arm64>/git
make build-amd64            # amd64 only
make build-arm64            # arm64 only
make smoketest ARCH=amd64   # re-run the standalone smoketest image
make package ARCH=amd64 SRC_DIR=/path/to/verified/source
```

The multi-stage `Dockerfile` (`source -> build -> smoketest -> export`)
downloads the upstream release tarball, verifies its GPG signature against
the pinned key in `keys/junio-hamano.asc`, builds a static binary against
musl with unneeded features compiled out, and gates the build on a
smoketest run inside a container with **no system git installed** - proving
there's no hidden dynamic dependency or PATH fallback masking a real gap.
See the Dockerfile's comments for the exact `NO_*` build flags in use and
why each one is set.

## Licensing

git itself is `GPL-2.0-only`. Every release tarball bundles its unmodified
`COPYING` file plus a `BUILD.md` documenting the exact upstream version and
build flags used.

The tooling in **this** repository (Dockerfile, scripts, CI) is licensed
separately under `AGPL-3.0-or-later` - see [LICENSE](LICENSE). GitCloud only
ever invokes the built binary as a subprocess (never links against it), so
this stays "mere aggregation" on GitCloud's side.
