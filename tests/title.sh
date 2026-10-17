#!/bin/sh
# The Console shows the app title (store appDB[<app>].title, from compose x-app.title). Kit schools know it as "Wikipedia".
set -eu
cd "$(dirname "$0")/.."
t=$(python3 -c 'import yaml,sys;print(yaml.safe_load(open("compose.yaml"))["x-app"]["title"])' 2>/dev/null || sed -n 's/^  title: //p' compose.yaml | head -1)
[ "$t" = "Wikipedia" ] || { echo "FAIL: x-app.title is '$t', expected 'Wikipedia'"; exit 1; }
echo "ok: x-app.title is Wikipedia"
