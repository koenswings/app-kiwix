#!/usr/bin/env bash
# app-kiwix on-Pi acceptance test (real image, real compose).
# Usage: tests/pi-test.sh <free-port> [evidence-dir]
# Exit 0 = pass. Writes an evidence folder (default ./pi-evidence-<host>-<UTC>).
# Refuses idea02 / wizardly-hugle (live pool). Requires arm64 unless ALLOW_NON_ARM64=1 (dry runs).
# Cleanup: compose down -v and temp dirs; the pinned image ghcr.io/kiwix/kiwix-serve:3.8.2 is kept.
set -uo pipefail
HOST=$(hostname -s 2>/dev/null || hostname)
case "${HOST,,}" in idea02|wizardly-hugle) echo "REFUSED: $HOST is a live pool host; use a dev Pi." >&2; exit 2;; esac
PORT=${1:-}
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT<1024 || PORT>65535 )); then echo "usage: $0 <free-port 1024-65535> [evidence-dir]" >&2; exit 2; fi
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then echo "REFUSED: port $PORT is in use" >&2; exit 2; fi
ARCH=$(uname -m)
[[ "$ARCH" == aarch64 || "$ARCH" == arm64 || "${ALLOW_NON_ARM64:-}" == 1 ]] || { echo "REFUSED: arch $ARCH is not arm64 (set ALLOW_NON_ARM64=1 for a dry run)" >&2; exit 2; }
cd "$(dirname "$0")/.." || exit 2
EV=${2:-"$PWD/pi-evidence-$HOST-$(date -u +%Y%m%dT%H%M%SZ)"}; mkdir -p "$EV"
{ echo "host=$HOST arch=$ARCH port=$PORT"; date -u; git rev-parse HEAD 2>/dev/null; docker version --format 'docker {{.Server.Version}} {{.Server.Arch}}'; docker compose version; } > "$EV/env.txt" 2>&1
docker ps -a --format '{{.Names}} {{.Image}}' | sort > "$EV/containers-before.txt"
docker image ls --format '{{.Repository}}:{{.Tag}}' | sort > "$EV/images-before.txt"
KIWIX_TEST_PORT=$PORT sh tests/test.sh > "$EV/test.log" 2>&1; rc=$?
docker ps -a --format '{{.Names}} {{.Image}}' | sort > "$EV/containers-after.txt"
docker image ls --format '{{.Repository}}:{{.Tag}}' | sort > "$EV/images-after.txt"
left=$(docker ps -a --format '{{.Names}}' | grep '^kiwixtest' || true)
if [[ -n "$left" ]]; then echo "FAIL: leftover containers: $left" >> "$EV/test.log"; rc=1; fi
newimg=$(comm -13 "$EV/images-before.txt" "$EV/images-after.txt" | grep -v '^ghcr.io/kiwix/kiwix-serve:3.8.2$' || true)
if [[ -n "$newimg" ]]; then echo "FAIL: unexpected new images: $newimg" >> "$EV/test.log"; rc=1; fi
cat "$EV/test.log"; echo "rc=$rc" > "$EV/result.txt"
[[ $rc == 0 ]] && echo "PI-TEST PASS — evidence: $EV" || echo "PI-TEST FAIL (rc=$rc) — evidence: $EV"
exit $rc
