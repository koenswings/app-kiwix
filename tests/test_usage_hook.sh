#!/bin/sh
# Unit tests for hooks/usage.sh — no docker required.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/hooks/usage.sh"
DAY=2026-11-12
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
LOGDIR="$tmp/logs"; DATADIR="$tmp/data"
mkdir -p "$LOGDIR" "$DATADIR"
pass=0
ok() { pass=$((pass+1)); echo "ok: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

run() { IDEA_USAGE_LOG_DIR="$LOGDIR" IDEA_USAGE_DATA_DIR="$DATADIR" sh "$HOOK" "$@"; }

# sample
out=$(run sample) || fail "sample exit"
echo "$out" | grep -q '"schema":"idea-usage-sample/1"' || fail "sample schema: $out"
echo "$out" | grep -q '"supported":false' || fail "sample supported: $out"
echo "$out" | grep -q '"app":"kiwix"' || fail "sample app"
case "$out" in *engine*|*instance*|*hookStatus*) fail "forbidden field in sample: $out" ;; esac
ok "sample unsupported"

# invalid
set +e
out=$(run day nope 2>"$tmp/err"); code=$?
set -e
[ "$code" = 2 ] || fail "invalid exit $code"
[ -z "$out" ] || fail "invalid wrote stdout"
grep -q invalid "$tmp/err" || fail "invalid stderr"
ok "invalid date rejected"

# empty day
out=$(run day "$DAY") || fail "empty day exit"
echo "$out" | grep -q '"pageViews":0' || fail "empty views: $out"
echo "$out" | grep -q '"sessions":0' || fail "empty sessions"
ok "missing log is zeros"

# build a log
cat > "$LOGDIR/access-$DAY.json" <<'LOG'
{"time":"2026-11-12T08:15:00+02:00","addr":"10.42.0.21","method":"GET","uri":"/content/wikipedia_en_all/A/Paris","status":200}
{"time":"2026-11-12T08:16:00+02:00","addr":"10.42.0.21","method":"GET","uri":"/skin/default.css","status":200}
{"time":"2026-11-12T08:16:10+02:00","addr":"10.42.0.21","method":"GET","uri":"/catalog/v2/entries","status":200}
{"time":"2026-11-12T08:16:20+02:00","addr":"10.42.0.21","method":"GET","uri":"/suggest?q=p","status":200}
{"time":"2026-11-12T08:17:00+02:00","addr":"10.42.0.21","method":"GET","uri":"/raw/wikipedia_en_all/content/A/France.png","status":200}
{"time":"2026-11-12T08:18:00+02:00","addr":"10.42.0.21","method":"GET","uri":"/raw/wikipedia_en_all/content/A/France","status":200}
{"time":"2026-11-12T08:19:00+02:00","addr":"10.42.0.21","method":"GET","uri":"/wikipedia_en_all/A/Lyon","status":302}
{"time":"2026-11-12T10:00:00+02:00","addr":"10.42.0.22","method":"GET","uri":"/content/wikipedia_en_all/A/Paris","status":200}
{"time":"2026-11-12T10:40:00+02:00","addr":"10.42.0.22","method":"GET","uri":"/content/wikipedia_en_all/A/Marseille","status":200}
{"time":"2026-11-11T10:00:00+02:00","addr":"10.42.0.21","method":"GET","uri":"/content/wikipedia_en_all/A/OtherDay","status":200}
LOG

out=$(run day "$DAY") || fail "day exit: $out"
echo "$out" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["schema"]=="idea-usage-day/1", o
assert o["day"]=="2026-11-12"
assert o["app"]=="kiwix"
assert o["pageViews"]==5, o  # Paris, France, Lyon (302), Paris, Marseille; not skin/catalog/suggest/png/other-day
assert o["distinctArticles"]==4, o  # Paris France Lyon Marseille
assert o["sessions"]==3, o  # .21 one session; .22 two sessions (40 min gap)
assert o["byHour"][8]==3, o["byHour"]  # paris+france+lyon (png dropped)
assert o["byHour"][10]==2, o["byHour"]
titles=sorted((x["title"], x["views"]) for x in o["topArticles"])
assert ("Paris", 2) in titles, o["topArticles"]
assert ("France", 1) in titles
blob=json.dumps(o)
assert "10.42.0" not in blob
assert "engine" not in o and "instance" not in o and "hookStatus" not in o
print("parsed", o["pageViews"], o["distinctArticles"], o["sessions"], titles)
'
ok "day aggregates, drops noise, no addresses"

# demo zim
: > "$DATADIR/wikipedia_en_simple_all_nopic.zim"
out=$(run day "$DAY") || fail "demo exit"
echo "$out" | grep -q '"demo":true' || fail "demo not true: $out"
ok "simple-English ZIM sets demo"

# piped stdin
out=$(IDEA_USAGE_LOG_DIR="$LOGDIR" IDEA_USAGE_DATA_DIR="$DATADIR" sh -s -- sample < "$HOOK") || fail "piped sample"
echo "$out" | grep -q '"supported":false' || fail "piped sample body"
ok "piped sh -s sample works"

echo "PASS ($pass checks)"
