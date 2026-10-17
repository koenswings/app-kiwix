#!/bin/sh
# app-kiwix tests. Needs docker + compose v2 and ghcr.io/kiwix/kiwix-serve:3.8.2
# (pulled if absent). Runs the REAL image through `docker compose up` with this
# compose.yaml, as the Engine does: no overridden entrypoint, no fake binary.
set -eu
sh "$(dirname "$0")/title.sh"
cd "$(dirname "$0")/.."
ROOT=$(pwd); IMG=ghcr.io/kiwix/kiwix-serve:3.8.2; PORT=${KIWIX_TEST_PORT:-18481}
pass=0; ok() { pass=$((pass+1)); echo "ok: $*"; }
t=$(mktemp -d); P=kiwixtest$$
dc() { (cd "$t" && port=$PORT docker compose -p $P -f compose.yaml "$@"); }
cleanup() { dc down -v >/dev/null 2>&1 || true; rm -rf "$t"; }
fail() { echo "FAIL: $*"; dc logs 2>/dev/null || true; cleanup; exit 1; }
trap cleanup EXIT

# 1. compose config contract
cfg=$(port=18480 docker compose -f compose.yaml config --format json)
echo "$cfg" | python3 -c '
import json,sys
c=json.loads(sys.stdin.read(),strict=False)["services"]["kiwix"]
assert c["image"]=="ghcr.io/kiwix/kiwix-serve:3.8.2", c["image"]
assert c["pull_policy"]=="never"
assert c["entrypoint"]==["/usr/bin/dumb-init","--","/bin/sh","-c"], c["entrypoint"]
assert "/data/*.zim" in c["command"][0] and "exec /usr/local/bin/kiwix-serve" in c["command"][0], c["command"]
v=c["volumes"][0]; assert v["target"]=="/data" and v.get("read_only") is True, v
p=c["ports"][0]; assert str(p["published"])=="18480" and p["target"]==8080, p
' || fail "compose config contract"
ok "compose config valid (image, pull_policy, shell entrypoint, ro volume, port)"
grep -q 'duration' compose.yaml && fail "fixture text left in compose.yaml"
ok "no duration-fixture leftovers"

docker image inspect $IMG >/dev/null 2>&1 || docker pull -q $IMG >/dev/null
cp compose.yaml "$t/"; mkdir "$t/data"

# 2. no ZIM: container exits non-zero with a clear error
: > "$t/data/notes.txt"
dc up -d >/dev/null 2>&1 || true
i=0; while [ "$(docker inspect -f '{{.State.Status}}' ${P}-kiwix-1 2>/dev/null)" != exited ]; do i=$((i+1)); [ $i -gt 30 ] && fail "no-zim: container did not exit"; sleep 1; done
[ "$(docker inspect -f '{{.State.ExitCode}}' ${P}-kiwix-1)" != 0 ] || fail "no-zim: exit code 0"
dc logs 2>&1 | grep -q 'ERROR: no .zim file in /data' || fail "no-zim: missing error message"
ok "no ZIM: exits non-zero with 'ERROR: no .zim file in /data'"
dc down >/dev/null 2>&1

# 3. real image + real (stub, CC0) ZIM under an arbitrary new name -> HTTP 200
cp tests/fixtures/stub.zim "$t/data/renamed_$(date +%s).zim"
dc up -d >/dev/null 2>&1 || fail "compose up"
i=0; until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/)" = 200 ]; do i=$((i+1)); [ $i -gt 30 ] && fail "no HTTP 200"; sleep 1; done
ok "compose up with renamed ZIM: HTTP 200 on /"
n=$(curl -fsS "http://127.0.0.1:$PORT/catalog/v2/entries" | grep -c '<entry>') || true
[ "${n:-0}" -ge 1 ] || fail "expected a catalog entry, got ${n:-0}"
ok "renamed ZIM in catalog ($n entries)"
dc logs 2>&1 | grep -q 'kiwix: serving /data/' || fail "no 'serving' log line"
ok "log shows served files"
echo "PASS ($pass checks)"
