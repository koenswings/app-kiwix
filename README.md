# app-kiwix
Compose file for the Kiwix app

ZIM files live in the instance `./data` folder (bind-mounted read-only at
`/data`). App data uses this relative `./data` bind, never a Docker named
volume ([idea#141](https://github.com/koenswings/idea/issues/141)). Access logs
go to a separate `./logs` bind (not under `./data`; see
[docs/usage-hook.md](docs/usage-hook.md)). `x-app.backup.method` is `none` and
`snapshotExclude` is `data`, so updates leave the ZIM files in place
([docs/backup.md](docs/backup.md)).

## Current release: 1.3-3.8.2

Current `x-app.version` and git tag: `1.3-3.8.2` (the image remains official `ghcr.io/kiwix/kiwix-serve:3.8.2`). A GitHub Release named “Zimbabwe delivery 20 Oct 2026” exists as tag `zimbabwe-2026-10-20`; that is a kit delivery tag, not a later App version.


- Image: official `ghcr.io/kiwix/kiwix-serve:3.8.2` (multi-arch, arm64), `pull_policy: never`, so pre-pull it on the Engine.
- Content: every `*.zim` in the instance `data/` folder is served (mounted read-only at `/data`). compose.yaml runs `/bin/sh -c` (under dumb-init) to expand `/data/*.zim` and exec kiwix-serve; with no ZIM the container exits with `ERROR: no .zim file in /data`. To change content, add, remove or rename ZIM files and restart. No env var is needed for ZIM names.
- Instance `.env`: only `port=<host port>` (container listens on 8080).
- Tests: `sh tests/test.sh` (docker + compose v2). Runs the real image via `docker compose up` with a renamed CC0 stub ZIM (tests/fixtures/stub.zim) and checks HTTP 200, plus the no-ZIM error.

## Release check against the previous release (idea#403)

- **Before tagging a release, run `script/check-base-ref.sh` in a full clone with tags, with `AAD_CHECK_COMPOSE` set:** `AAD_CHECK_COMPOSE=<agent-app-dev>/script/check-compose.mjs script/check-base-ref.sh`.
- It compares `compose.yaml` with the previous release tag (agent-app-dev `check-compose --base-ref`). A stateful image (MariaDB, MySQL, Postgres, Mongo, Redis) that moves to a new series needs an App major bump.
- **Previous release tag:** the highest `<major>.<minor>[-<upstream>]` tag that is an ancestor of HEAD and is not HEAD's own tag.
- **It fails** in a shallow clone (`git fetch --unshallow --tags`; CI: `fetch-depth: 0`) and in a clone with no release tags at all (`git fetch --tags`).
- **First release:** if the repo has release tags but none of them is an ancestor, it is skipped with a note. If there are no release tags at all, a real first release must set `CHECK_BASE_REF_FIRST_RELEASE=1`.
- `node --test tests/release-base-ref.test.mjs` tests it. The compare runs only when `AAD_CHECK_COMPOSE` is set.
