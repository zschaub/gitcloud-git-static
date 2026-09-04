# Project Purpose

This project builds and publishes minimal, statically-linked `git` binaries for Linux, for one consumer: the [GitCloud](https://github.com/zschaub/gitcloud) Nextcloud app, which needs to bundle a working `git` executable so it can run inside environments where installing `git` isn't possible — chiefly Nextcloud AIO, whose container filesystem is replaced on every update, so nothing installed into it by hand persists.

This is not a general-purpose "portable git" project. Scope everything to what GitCloud actually needs.

## What GitCloud actually needs from git

GitCloud never performs a remote operation — no clone, fetch, push, pull, or remotes of any kind. It only runs local plumbing against a repo it fully owns:

- `init`
- `add`
- `commit` (always with `-m`, never opens `$EDITOR`)
- `checkout <hash> -- <path>`
- `status --porcelain -z`
- `config --get` / `config --set` (used to set `user.name`/`user.email` before the first commit — never relies on system user lookup)
- `rev-parse HEAD`
- `log`

No hooks, no templates, no submodules, no LFS, no credential helpers, no network transport (http/https/ssh) of any kind. Treat any of those as explicitly out of scope unless GitCloud's own requirements change — check with the user/GitCloud's own repo before adding scope, don't assume future need.

## Build approach

- Build **vanilla upstream git from an official, signed release tarball** — no custom patches unless a real, documented necessity comes up. Pin an exact upstream version per build; note it in the release.
- Link **statically against musl libc**, not glibc. glibc's NSS (user/hostname resolution) doesn't work reliably when statically linked; musl doesn't have that problem, and GitCloud never needs it anyway (identity comes from `git config`, not system user lookup) — but musl avoids the risk entirely.
- Disable everything not needed, using git's own supported `NO_*` Makefile flags: `NO_OPENSSL=1 NO_CURL=1 NO_PERL=1 NO_TCLTK=1` (and evaluate `NO_PYTHON=1`, `NO_GETTEXT=1` similarly — anything that isn't needed for the command list above). These are official, documented git build options — disabling them degrades gracefully (an unsupported subcommand prints an error) rather than breaking the build. Confirm the exact flag set actually needed empirically, don't just copy this list uncritically.
- A real prior-art reference worth studying (not necessarily reusing as-is): [`darkvertex/static-git`](https://github.com/darkvertex/static-git) ships working dependency-free static git for Linux amd64 today, built via Docker + Earthly. It has **no arm64 build** — that gap is exactly what this project needs to fill; don't assume arm64 "just works" the same way without testing it.

## Architectures

- **amd64**: primary target, most precedented.
- **arm64**: required (Raspberry Pi 4/5 64-bit, Apple Silicon Docker hosts, AWS Graviton — real Nextcloud AIO hosts). Build and verify independently; don't assume the amd64 build's behavior carries over.
- 32-bit x86 and 32-bit ARM (armv7): not currently in scope — Docker/AIO is effectively 64-bit-only today. Revisit only if there's a concrete request.

## Required verification before any release is trusted

Every release must be exercised by an automated smoke test — not just "it compiled" — that runs the exact GitCloud command list above, in order, inside a minimal container that has **no system git installed** (to prove there's no hidden dynamic dependency or PATH fallback masking a real gap). At minimum: `init` a repo, `add` a file, `config --set` a fake identity, `commit -m`, `rev-parse HEAD`, modify the file, `status --porcelain -z`, `checkout <hash> -- <path>` to confirm rollback content matches, `log`. A build that compiles but hasn't passed this smoke test is not release-ready.

## Distribution

- Publish binaries **only as checksummed (sha256) GitHub Release assets** — one archive per architecture, named with both the git version and target arch (e.g. `git-static-linux-amd64-2.47.0.tar.gz`).
- **Never commit built binaries into this repo's git history.** Binary blobs never diff away and bloat `.git` permanently — releases are the only distribution channel.
- GitCloud's own release pipeline is expected to download a specific pinned version + verify its checksum before bundling — this project doesn't need to push anything into GitCloud; GitCloud pulls from here.

## Licensing

git is `GPL-2.0-only`. Redistributing compiled binaries obligates this project to include git's own `COPYING` file in every release archive and clearly document the exact upstream version and build-flag deviations from stock git. GitCloud only ever invokes the binary as a subprocess (never links against it), so this stays "mere aggregation" on GitCloud's side — but this project, as the thing actually redistributing the compiled binary, should get its own license compliance right regardless.

## Release cadence

Track upstream git's own release/security schedule, not GitCloud's. A new upstream git release (especially a security fix) should get a rebuild and new release here promptly, independent of whatever GitCloud's own version/release cycle is doing.

## Working style

- Verify claims empirically before trusting them — this whole project exists because an earlier "should work in theory" assumption about static git needed real checking (see the smoke-test requirement above). Don't repeat that pattern here: build it, run the smoke test, then trust it.
- Keep scope narrow. This project has exactly one consumer with a fixed, small command surface — resist adding functionality (network transports, hooks, other platforms) that GitCloud doesn't use, even if git itself supports it.
