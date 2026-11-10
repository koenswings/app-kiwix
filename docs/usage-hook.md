# Usage hook and access log (idea#413)

Kiwix ships an nginx proxy in front of `kiwix-serve` and a hook at `hooks/usage.sh`, mounted into the `proxy` service at `/hooks/usage.sh`.

The Engine (`agent-engine-dev#308`) invokes:

```
docker compose exec -T proxy /hooks/usage.sh day YYYY-MM-DD
docker compose exec -T proxy /hooks/usage.sh sample
```

Unlisted containers borrow the file via `sh -s`. The hook is POSIX `sh` + `awk` (the nginx image has no Python).

## Declaration

```yaml
x-app:
  usage:
    service: proxy
    command: /hooks/usage.sh
    timeoutS: 30
```

Backup stays none. Access logs are not application data.

## Proxy and logs

- `proxy` publishes `${port}:8080` and reverse-proxies to `kiwix:8080` on the compose network.
- `kiwix-serve` has no host port.
- JSON access logs are written to the `./logs` bind (not a named volume, not under `./data`) as `access-YYYY-MM-DD.json`.
- The proxy entrypoint creates `/logs`, and both the entrypoint and the hook prune files older than 14 days.

## Output

| Mode | Schema | Notes |
|------|--------|--------|
| `day YYYY-MM-DD` | `idea-usage-day/1` | `pageViews`, `distinctArticles`, `sessions`, `topArticles` (capped at 50), `byHour` (24 kit-local hours). |
| `sample` | `idea-usage-sample/1` | `"supported": false`. |

The hook never prints `engine`, `instance`, `name`, `listed`, `clock`, `collectedAt`, `hookStatus` or `skipReason`.

Page views count `/content/…`, `/raw/…/content/…` and legacy `/A/` or `/*/A/` article paths. Skin, catalog, suggest, search, raw meta and media extensions are dropped. Sessions are counted with a 30-minute idle gap on the client address; the address itself is never emitted. `demo` is `true` when a ZIM filename under `./data` contains `simple`.

Override paths in tests with `IDEA_USAGE_LOG_DIR` and `IDEA_USAGE_DATA_DIR`.

Run `tests/test_usage_hook.sh` (no Docker).
