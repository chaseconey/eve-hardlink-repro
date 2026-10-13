#!/usr/bin/env bash
# Runs one build case inside a Linux container (or a CI runner with root).
#
#   normal   build on an ordinary disk (expected: success)
#   nolinks  build with .eve on a filesystem without hard links (expected: link() error)
#   patched  same as nolinks, with the suggested rename fallback applied to eve (expected: success)
#
# A FAT image stands in for the filesystem without hard links because it can
# be mounted anywhere. The original failure was on an NFSv4 mount (AWS
# Bedrock AgentCore session storage) where link() fails with errno 524.
set -euo pipefail
CASE=${1:?usage: build-case.sh normal|nolinks|patched}
SRC=${SRC:-$(cd "$(dirname "$0")/.." && pwd)}
APP=/tmp/app-$CASE

command -v rsync >/dev/null && command -v mkfs.vfat >/dev/null || {
  apt-get update -qq >/dev/null && apt-get install -y -qq dosfstools rsync >/dev/null
}

rm -rf "$APP" && mkdir -p "$APP"
rsync -a --exclude node_modules --exclude .eve --exclude .output --exclude .git "$SRC/" "$APP/"
cd "$APP"
echo "node $(node -v), npm $(npm -v)"
npm ci --no-audit --no-fund --loglevel=error
echo "eve $(node -p 'require("eve/package.json").version')"

if [ "$CASE" != normal ]; then
  # Only .eve goes on the no-hard-link filesystem, so npm can still create the
  # node_modules/.bin symlinks (FAT has no symlinks either; NFS does).
  truncate -s 1G /tmp/nolinks-$CASE.img
  mkfs.vfat -F 32 /tmp/nolinks-$CASE.img >/dev/null
  mkdir -p .eve && mount -o loop /tmp/nolinks-$CASE.img .eve
  echo a > .eve/probe
  if ln .eve/probe .eve/probe-link 2>/dev/null; then echo "unexpected: hard links work on .eve"; exit 2; fi
  echo "confirmed: .eve is on a filesystem without hard links"
  rm -f .eve/probe
fi

if [ "$CASE" = patched ]; then
  f=node_modules/eve/dist/src/internal/authored-module-map-loader.js
  old='try{await link(s,o)}catch(e){if(e.code!==`EEXIST`)throw e}'
  new='try{await link(s,o)}catch(e){if(e.code!==`EEXIST`)await rename(s,o)}'
  grep -qF "$old" "$f" || { echo "patch target not found in $f"; exit 2; }
  sed -i "s/import{link,mkdir,unlink,writeFile}from\"node:fs\/promises\"/import{link,mkdir,rename,unlink,writeFile}from\"node:fs\/promises\"/" "$f"
  OLD="$old" NEW="$new" node -e 'const fs=require("fs");const f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace(process.env.OLD,process.env.NEW))' "$f"
  echo "applied rename fallback to $f"
fi

# Build output (.output) lands on the normal disk; eve renames it out of .eve,
# which would fail across mounts for an unrelated reason, so stop after compile
# succeeds if .eve is a separate mount.
set +e
npm run build 2>&1 | tee /tmp/build-$CASE.log
status=${PIPESTATUS[0]}
set -e

if [ "$CASE" != normal ] && grep -q "EXDEV: cross-device link not permitted, rename" /tmp/build-$CASE.log; then
  echo "build compiled and bundled; only the final cross-mount rename of .output failed (a side effect of this test's mount layout)"
  status=0
fi
umount .eve 2>/dev/null || true
echo "case=$CASE build exit=$status"
exit $status
