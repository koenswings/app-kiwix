#!/bin/sh
# idea#403: x-app.backup method none (agent-engine-dev#404). No docker needed.
# Also runs agent-app-dev check-compose --release when AAD_CHECK_COMPOSE points at it.
set -eu
cd "$(dirname "$0")/.."
pass=0; ok() { pass=$((pass+1)); echo "ok: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
VER=1.3-3.8.2
grep -A1 '^  backup:$' compose.yaml | grep -q '^    method: none$' || fail "x-app.backup method none"
ok "x-app.backup method none"
for k in preHook postHook hookExclude hookTimeout fallback verify; do
  grep -q "^    $k:" compose.yaml && fail "$k is only for method hook"
done
ok "no hook keys"
grep -q "^  version: \"$VER\"$" compose.yaml || fail "x-app.version $VER"
n=$(grep -c "^      x-app-version: \"$VER\"$" compose.yaml); [ "$n" = 2 ] || fail "x-app-version labels: $n"
ok "version $VER on x-app and both services"
grep -q 'backup.md' docs/INDEX.md || fail "docs/INDEX.md links backup.md"
ok "docs"
if [ -n "${AAD_CHECK_COMPOSE:-}" ]; then
  node "$AAD_CHECK_COMPOSE" --release --tag "$VER" compose.yaml || fail "check-compose"
  ok "agent-app-dev check-compose --release --tag $VER"
fi
echo "PASS ($pass)"
