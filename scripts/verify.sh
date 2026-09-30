#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift test "$@"
"$root/scripts/build-app.sh" "$@"
"$root/scripts/package-release.sh"
