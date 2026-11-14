# Backup: method `none` (idea#403)

Kiwix sets `x-app.backup.method: none` (1.3-3.8.2, agent-engine-dev#404).

**Why:** the instance holds only ZIM files (read-only content, mounted `:ro`) and nginx access
logs. ZIM files are re-downloadable from the Kiwix library and can be many GB, so a backup would
fill the Backup Disk with content that is not school data. The access logs in `logs/` only feed
the usage hook (`docs/usage-hook.md`), which the Engine reads every day.

**What the Engine does** for a `backupApp` of Kiwix: no borg run, no lock, no stop, no hooks, no
cleanup and no `lastBackup`. The operation is Done with `args.hookResult: 'none'` and
`lastResult {method: none, result: OK}`. `exclude`, `hookExclude`, `preHook`, `postHook` and
`verify` are not used (agent-app-dev check-compose rejects the hook keys with method none).

**Recovery** after a lost disk: install Kiwix again and copy the ZIM files back into `data/`.

Tests: `sh tests/backup.sh` (no docker; set `AAD_CHECK_COMPOSE` to agent-app-dev
`script/check-compose.mjs` to also run check-compose). `sh tests/test.sh` asserts the same block
through `docker compose config`.
