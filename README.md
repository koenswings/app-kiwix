# app-kiwix
Compose file for the Kiwix app

## 1.0

- Image: official `ghcr.io/kiwix/kiwix-serve:3.8.2` (multi-arch, arm64), `pull_policy: never`, so pre-pull it on the Engine.
- Content: every `*.zim` in the instance `data/` folder is served (mounted read-only at `/data`). The image's `start.sh` expands the `*.zim` argument in its `/data` workdir. To change content, add, remove or rename ZIM files and restart. No env var is needed for ZIM names.
- Instance `.env`: only `port=<host port>` (container listens on 8080).
- Tests: `sh tests/test.sh` (docker + compose v2). Set `KIWIX_TEST_ZIM=/path/x.zim` for a live serve check.
