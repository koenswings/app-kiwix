#!/bin/sh
# hooks/usage.sh — Kiwix usage hook (idea#413)
# Contract: koenswings/agent-engine-dev#308 docs/USAGE-CONTRACT.md
# Runs in the proxy service (reads /logs). Also works when piped to sh -s.
set -eu
MODE=${IDEA_USAGE_MODE:-${1:-}}
DAY=${IDEA_USAGE_DAY:-${2:-}}
LOG_DIR=${IDEA_USAGE_LOG_DIR:-/logs}
DATA_DIR=${IDEA_USAGE_DATA_DIR:-/data}

json_one() { printf '%s\n' "$1"; }

if [ "$MODE" = sample ]; then
  json_one '{"schema":"idea-usage-sample/1","app":"kiwix","supported":false}'
  exit 0
fi
echo "$DAY" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || {
  echo "invalid arguments" >&2
  exit 2
}

# Drop rolled logs older than 14 days (same rule as the proxy entrypoint).
now=$(date +%s)
cutoff=""
if date -u -d "@$((now - 14 * 86400))" +%Y-%m-%d >/dev/null 2>&1; then
  cutoff=$(date -u -d "@$((now - 14 * 86400))" +%Y-%m-%d)
elif date -u -r "$((now - 14 * 86400))" +%Y-%m-%d >/dev/null 2>&1; then
  cutoff=$(date -u -r "$((now - 14 * 86400))" +%Y-%m-%d)
fi
if [ -n "$cutoff" ]; then
  for f in "$LOG_DIR"/access-*.json; do
    [ -f "$f" ] || continue
    base=${f##*/}
    ymd=${base#access-}
    ymd=${ymd%.json}
    if [ "$ymd" \< "$cutoff" ]; then
      rm -f "$f"
    fi
  done
fi

demo=false
for z in "$DATA_DIR"/*.zim; do
  [ -f "$z" ] || continue
  case "$z" in
    *simple*|*Simple*) demo=true ;;
  esac
done

LOG="$LOG_DIR/access-$DAY.json"
if [ ! -f "$LOG" ]; then
  json_one '{"schema":"idea-usage-day/1","day":"'"$DAY"'","app":"kiwix","demo":'"$demo"',"pageViews":0,"distinctArticles":0,"sessions":0,"topArticles":[],"byHour":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}'
  exit 0
fi

# awk: parse our JSON access log, classify page views, sessionise, emit one JSON object.
# Does not print client addresses.
demo_json=$demo DAY="$DAY" awk '
function extract_str(s, key,   p, rest, q, needle) {
  needle = "\"" key "\":\""
  p = index(s, needle)
  if (p == 0) return ""
  rest = substr(s, p + length(needle))
  q = index(rest, "\"")
  if (q == 0) return rest
  return substr(rest, 1, q - 1)
}
function extract_num(s, key,   p, rest, q, needle, ch, i, out) {
  needle = "\"" key "\":"
  p = index(s, needle)
  if (p == 0) return ""
  rest = substr(s, p + length(needle))
  out = ""
  for (i = 1; i <= length(rest); i++) {
    ch = substr(rest, i, 1)
    if (ch ~ /[0-9]/) out = out ch
    else if (out != "") break
  }
  return out
}
function isleap(y) { return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) }
function ymd_min(y, m, d, hh, mm,   i, dim, days) {
  days = 0
  for (i = 1970; i < y; i++) days += isleap(i) ? 366 : 365
  dim[1]=31; dim[2]=isleap(y)?29:28; dim[3]=31; dim[4]=30; dim[5]=31; dim[6]=30
  dim[7]=31; dim[8]=31; dim[9]=30; dim[10]=31; dim[11]=30; dim[12]=31
  for (i = 1; i < m; i++) days += dim[i]
  days += d - 1
  return days * 1440 + hh * 60 + mm
}
function parse_mins(ts,   y, mo, d, hh, mm) {
  y = substr(ts, 1, 4) + 0
  mo = substr(ts, 6, 2) + 0
  d = substr(ts, 9, 2) + 0
  hh = substr(ts, 12, 2) + 0
  mm = substr(ts, 15, 2) + 0
  if (y < 1970) return 0
  return ymd_min(y, mo, d, hh, mm)
}
function json_esc(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/"/, "\\\"", s)
  return s
}
function hex2dec(h,   i, c, v, n) {
  n = 0
  for (i = 1; i <= length(h); i++) {
    c = substr(h, i, 1)
    if (c >= "0" && c <= "9") v = c + 0
    else if (c == "a" || c == "A") v = 10
    else if (c == "b" || c == "B") v = 11
    else if (c == "c" || c == "C") v = 12
    else if (c == "d" || c == "D") v = 13
    else if (c == "e" || c == "E") v = 14
    else if (c == "f" || c == "F") v = 15
    else v = 0
    n = n * 16 + v
  }
  return n
}
function urldecode(s,   out, i, c, hex) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "%" && i + 2 <= length(s)) {
      hex = substr(s, i+1, 2)
      if (hex ~ /^[0-9A-Fa-f][0-9A-Fa-f]$/) {
        out = out sprintf("%c", hex2dec(hex))
        i += 2
        continue
      }
    }
    if (c == "+") c = " "
    out = out c
  }
  return out
}
function is_media(uri,   ext) {
  ext = uri
  sub(/.*\./, "", ext)
  ext = tolower(ext)
  return ext ~ /^(jpg|jpeg|png|gif|svg|webp|ico|bmp|mp3|mp4|webm|ogg|wav|avi|mov|css|js|mjs|woff|woff2|ttf|eot|map|wasm|iso)$/
}
function is_dropped(uri) {
  return uri ~ /^\/skin(\/|$)/ || uri ~ /^\/catalog(\/|$)/ || uri ~ /^\/suggest(\/|$)/ || uri ~ /^\/search(\/|$)/ || uri ~ "^/raw/[^/]+/meta(/|$)"
}
function is_legacy(uri) {
  return uri ~ /^\/A\// || uri ~ "^/[^/]+/A/"
}
function is_content(uri) {
  return uri ~ /^\/content\// || uri ~ "^/raw/[^/]+/content/"
}
function article_of(uri,   rest, n, parts, i, out) {
  rest = uri
  if (rest ~ /^\/content\//) {
    rest = substr(rest, 10)
    n = split(rest, parts, "/")
    out = ""
    for (i = 2; i <= n; i++) out = out (i == 2 ? "" : "/") parts[i]
    return out
  }
  if (match(rest, "^/raw/[^/]+/content/")) {
    rest = substr(rest, RLENGTH + 1)
    return rest
  }
  if (rest ~ /^\/A\//) return substr(rest, 4)
  if (match(rest, "^/[^/]+/A/")) return substr(rest, RLENGTH + 1)
  return rest
}
function prettify(s) {
  # Drop the ZIM article namespace (A/...) so titles read as "Paris", not "A/Paris".
  if (s ~ /^A\//) s = substr(s, 3)
  s = urldecode(s)
  gsub(/_/, " ", s)
  return s
}
BEGIN {
  day = ENVIRON["DAY"]
  demo = ENVIRON["demo_json"]
  pageViews = 0
  sessions = 0
  split("", hours)
  for (i = 0; i < 24; i++) hours[i] = 0
}
{
  time = extract_str($0, "time")
  addr = extract_str($0, "addr")
  uri = extract_str($0, "uri")
  status = extract_num($0, "status") + 0
  if (uri == "" || time == "") next
  if (substr(time, 1, 10) != day) next
  if (is_dropped(uri) || is_media(uri)) next
  content = is_content(uri)
  legacy = is_legacy(uri)
  if (!(content || legacy)) next
  if (content && status != 200 && status != 304) next
  if (legacy && !content && status != 200 && status != 304 && status != 301 && status != 302) next
  title = prettify(article_of(uri))
  if (title == "") next
  pageViews++
  hour = substr(time, 12, 2) + 0
  if (hour < 0 || hour > 23) hour = 0
  hours[hour]++
  views[title]++
  if (!(title in seenart)) { seenart[title] = 1; nart++ }
  nrec++
  rec_addr[nrec] = addr
  rec_min[nrec] = parse_mins(time)
}
END {
  # sessionise by address with a 30-minute idle gap (addresses stay here)
  for (i = 1; i <= nrec; i++) {
    a = rec_addr[i]; m = rec_min[i]
    idx = ++gcount[a]
    gaddr[a, idx] = m
  }
  for (a in gcount) {
    n = gcount[a]
    # simple insertion sort of that address timestamps
    for (i = 2; i <= n; i++) {
      key = gaddr[a, i]; j = i - 1
      while (j >= 1 && gaddr[a, j] > key) { gaddr[a, j+1] = gaddr[a, j]; j-- }
      gaddr[a, j+1] = key
    }
    sessions++
    prev = gaddr[a, 1]
    for (i = 2; i <= n; i++) {
      if (gaddr[a, i] - prev > 30) sessions++
      prev = gaddr[a, i]
    }
  }
  # top articles (cap 50)
  ntop = 0
  for (t in views) {
    ntop++
    titles[ntop] = t
    tviews[ntop] = views[t]
  }
  for (i = 1; i <= ntop; i++) {
    for (j = i + 1; j <= ntop; j++) {
      if (tviews[j] > tviews[i] || (tviews[j] == tviews[i] && titles[j] < titles[i])) {
        tv = tviews[i]; tviews[i] = tviews[j]; tviews[j] = tv
        tt = titles[i]; titles[i] = titles[j]; titles[j] = tt
      }
    }
  }
  if (ntop > 50) ntop = 50
  printf "{\"schema\":\"idea-usage-day/1\",\"day\":\"%s\",\"app\":\"kiwix\",\"demo\":%s,", day, demo
  printf "\"pageViews\":%d,\"distinctArticles\":%d,\"sessions\":%d,\"topArticles\":[", pageViews, nart+0, sessions
  for (i = 1; i <= ntop; i++) {
    if (i > 1) printf ","
    printf "{\"title\":\"%s\",\"views\":%d}", json_esc(titles[i]), tviews[i]
  }
  printf "],\"byHour\":["
  for (i = 0; i < 24; i++) {
    if (i > 0) printf ","
    printf "%d", hours[i]
  }
  printf "]}\n"
}
' "$LOG"
