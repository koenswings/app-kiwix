#!/bin/sh
# Prepare the access-log directory and drop files older than 14 days, then start nginx.
set -eu
mkdir -p /logs
# nginx workers (uid nginx) must be able to write the daily JSON logs.
if id nginx >/dev/null 2>&1; then
  chown -R nginx:nginx /logs 2>/dev/null || chmod 0777 /logs
else
  chmod 0777 /logs
fi
now=$(date +%s)
for f in /logs/access-*.json; do
  [ -f "$f" ] || continue
  base=${f##*/}
  ymd=${base#access-}
  ymd=${ymd%.json}
  case "$ymd" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) continue ;;
  esac
  # Portable age check: compare YYYY-MM-DD lexicographically against a cutoff.
done
# Cutoff date (UTC) 14 days ago, computed without GNU date -d when possible.
cutoff=""
if date -u -d "@$((now - 14 * 86400))" +%Y-%m-%d >/dev/null 2>&1; then
  cutoff=$(date -u -d "@$((now - 14 * 86400))" +%Y-%m-%d)
elif date -u -r "$((now - 14 * 86400))" +%Y-%m-%d >/dev/null 2>&1; then
  cutoff=$(date -u -r "$((now - 14 * 86400))" +%Y-%m-%d)
fi
if [ -n "$cutoff" ]; then
  for f in /logs/access-*.json; do
    [ -f "$f" ] || continue
    base=${f##*/}
    ymd=${base#access-}
    ymd=${ymd%.json}
    if [ "$ymd" \< "$cutoff" ]; then
      rm -f "$f"
    fi
  done
fi
exec nginx -g 'daemon off;'
