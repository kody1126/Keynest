#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-home-layout-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache=/private/tmp/keynest-home-layout-module-cache
mkdir -p "$module_cache"
xcrun swiftc -swift-version 5 -strict-concurrency=complete -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
  "$package_dir/Sources/KeynestApp/HomeLayoutReorder.swift" "$script_dir/HomeLayoutChecks.swift" \
  -o "$work_dir/home-layout-checks"
"$work_dir/home-layout-checks"
