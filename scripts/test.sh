#!/usr/bin/env bash
# Runs the test suite. With only Command Line Tools installed (no Xcode), swift-testing lives
# outside the default search paths, and its location differs between Swift versions
# (Frameworks/ in 6.3, usr/lib/ in older releases), so both are added explicitly.
# Some CLT releases also ship without the _Testing_Foundation cross-import overlay, which the
# tests don't need, so cross-import overlays are disabled.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLT_DEV="/Library/Developer/CommandLineTools/Library/Developer"

if [[ "$(xcode-select -p)" != /Library/Developer/CommandLineTools* ]]; then
  exec swift test --package-path "$ROOT" "$@"
fi

flags=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
for dir in "$CLT_DEV/Frameworks" "$CLT_DEV/usr/lib"; do
  [[ -d "$dir" ]] || continue
  flags+=(
    -Xswiftc -F -Xswiftc "$dir"
    -Xswiftc -I -Xswiftc "$dir"
    -Xlinker -F -Xlinker "$dir"
    -Xlinker -L -Xlinker "$dir"
    -Xlinker -rpath -Xlinker "$dir"
  )
done

exec swift test --package-path "$ROOT" "${flags[@]}" "$@"
