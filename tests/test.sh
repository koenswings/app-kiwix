#!/bin/sh
# app-kiwix tests. Needs docker + compose v2. Pulls ghcr.io/kiwix/kiwix-serve:3.8.2
# if absent. Optional: KIWIX_TEST_ZIM=/path/to/real.zim for a live HTTP check.
set -eu
cd "$(dirname "$0")/.."
IMG=ghcr.io/kiwix/kiwix-serve:3.8.2
pass=0; fail() { echo "FAIL: $*"; exit 1; }; ok() { pass=$((pass+1)); echo "ok: $*"; }

# 1. compose config validates and keeps the contract
cfg=$(port=18480 docker compose -f compose.yaml config --format json)
echo "$cfg" | python3 -c '
import json,sys
c=json.loads(sys.stdin.read(),strict=False)["services"]["kiwix"]
assert c["image"]=="ghcr.io/kiwix/kiwix-serve:3.8.2", c["image"]
assert c["pull_policy"]=="never"
assert c["command"]==["*.zim"], c["command"]
v=c["volumes"][0]; assert v["target"]=="/data" and v.get("read_only") is True, v
p=c["ports"][0]; assert str(p["published"])=="18480" and p["target"]==8080, p
' || fail "compose config contract"
ok "compose config valid (image, pull_policy, command, ro volume, port)"
grep -q 'duration' compose.yaml && fail "fixture text left in compose.yaml"
ok "no duration-fixture leftovers"

# 2. the real entrypoint expands *.zim in /data (fake kiwix-serve echoes its args)
docker image inspect $IMG >/dev/null 2>&1 || docker pull -q $IMG >/dev/null
t=$(mktemp -d); trap 'rm -rf "$t"; docker rm -f kiwix-test >/dev/null 2>&1 || true' EXIT
mkdir "$t/data"; : > "$t/data/wikipedia_en-simple_all_nopic_2026-09.zim"; : > "$t/data/other_renamed.zim"; : > "$t/data/notes.txt"
printf '#!/bin/sh\necho "ARGS: $*"\n' > "$t/fake"; chmod 755 "$t/fake"
out=$(docker run --rm -v "$t/data:/data:ro" -v "$t/fake:/usr/local/bin/kiwix-serve:ro" $IMG '*.zim')
echo "$out" | grep -q 'ARGS: --port=8080 .*other_renamed.zim' || fail "glob: $out"
echo "$out" | grep -q 'wikipedia_en-simple_all_nopic_2026-09.zim' || fail "glob: $out"
echo "$out" | grep -q 'notes.txt' && fail "non-zim served: $out"
ok "entrypoint serves every renamed *.zim, skips non-zim"

# 3. optional live check with a real ZIM under an arbitrary new name
if [ -n "${KIWIX_TEST_ZIM:-}" ]; then
  rm -f "$t"/data/*; cp "$KIWIX_TEST_ZIM" "$t/data/renamed_$(date +%s).zim"
  docker run -d --name kiwix-test -p 18481:8080 -v "$t/data:/data:ro" $IMG '*.zim' >/dev/null
  i=0; until curl -fsS http://127.0.0.1:18481/ >/dev/null 2>&1; do i=$((i+1)); [ $i -gt 30 ] && { docker logs kiwix-test; fail "live serve"; }; sleep 1; done
  curl -fsS "http://127.0.0.1:18481/catalog/v2/entries" | grep -q '<entry>' || fail "no catalog entry"
  ok "live kiwix-serve serves renamed real ZIM"
fi
echo "PASS ($pass checks)"
