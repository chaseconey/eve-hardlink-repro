#!/usr/bin/env bash
# Runs all three cases in Docker. --privileged is needed for the loop mount.
set -uo pipefail
cd "$(dirname "$0")"
run() { docker run --rm --privileged -v "$PWD":/src:ro -e SRC=/src node:24-bookworm bash /src/scripts/build-case.sh "$1"; }
run normal;  normal=$?
run nolinks; nolinks=$?
run patched; patched=$?
echo
echo "normal  (expected 0):        $normal"
echo "nolinks (expected non-zero): $nolinks"
echo "patched (expected 0):        $patched"
[ "$normal" -eq 0 ] && [ "$nolinks" -ne 0 ] && [ "$patched" -eq 0 ]
