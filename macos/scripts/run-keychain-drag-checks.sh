#!/bin/bash
# Pure grab-point math. Does not link the App, SceneKit, or any vault source.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-keychain-drag-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="$work_dir/module-cache"
mkdir -p "$module_cache"
cp "$package_dir/Sources/KeynestApp/KeychainDragGeometry.swift" "$work_dir/KeychainDragGeometry.swift"
cp "$script_dir/KeychainDragChecks.swift" "$work_dir/KeychainDragChecks.swift"
CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
    "$work_dir/KeychainDragGeometry.swift" "$work_dir/KeychainDragChecks.swift" \
    -o "$work_dir/keynest-keychain-drag-checks"
"$work_dir/keynest-keychain-drag-checks"
