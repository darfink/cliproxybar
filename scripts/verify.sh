#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
python3 -m unittest discover -s scripts/tests -v
swift test "$@"
"$root/scripts/build-app.sh" "$@"
"$root/scripts/package-release.sh"
