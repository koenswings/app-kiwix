# app-kiwix
Compose file for the Kiwix app

## 1.0

- Image: official `ghcr.io/kiwix/kiwix-serve:3.8.2` (multi-arch, arm64), `pull_policy: never`, so pre-pull it on the Engine.
- Content: every `*.zim` in the instance `data/` folder is served (mounted read-only at `/data`). compose.yaml runs `/bin/sh -c` (under dumb-init) to expand `/data/*.zim` and exec kiwix-serve; with no ZIM the container exits with `ERROR: no .zim file in /data`. To change content, add, remove or rename ZIM files and restart. No env var is needed for ZIM names.
- Instance `.env`: only `port=<host port>` (container listens on 8080).
- Tests: `sh tests/test.sh` (docker + compose v2). Runs the real image via `docker compose up` with a renamed CC0 stub ZIM (tests/fixtures/stub.zim) and checks HTTP 200, plus the no-ZIM error.

## Release check against the previous release (idea#403)

`AAD_CHECK_COMPOSE=<agent-app-dev>/script/check-compose.mjs script/check-base-ref.sh` compares `compose.yaml` with the previous release tag (agent-app-dev `check-compose --base-ref`): a stateful image (MariaDB, MySQL, Postgres, Mongo, Redis) that moves to a new series needs an App major bump. The previous release tag is the highest `<major>.<minor>[-<upstream>]` tag that is an ancestor of HEAD and not HEAD's own tag; a first release is skipped with a note. It needs tags and full history (CI: `fetch-depth: 0`); a shallow clone fails.
