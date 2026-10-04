#!/bin/bash
# Compile the real decorative scene source, but execute only its pure motion
# state. No NSApplication/window/renderer, credentials, network or hardware.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-keychain-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="$work_dir/module-cache"
mkdir -p "$module_cache"

# Stable inputs while an independent app build or editor runs in parallel.
cp "$package_dir/Sources/KeynestApp/KeychainSceneView.swift" "$work_dir/KeychainSceneView.swift"
cp "$package_dir/Sources/KeynestApp/KeychainMeshAsset.swift" "$work_dir/KeychainMeshAsset.swift"
cp "$package_dir/Sources/KeynestApp/KeychainDragGeometry.swift" "$work_dir/KeychainDragGeometry.swift"
cp "$script_dir/KeychainChecks.swift" "$work_dir/KeychainChecks.swift"

CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
    "$work_dir/KeychainSceneView.swift" "$work_dir/KeychainMeshAsset.swift" "$work_dir/KeychainDragGeometry.swift" "$work_dir/KeychainChecks.swift" \
    -o "$work_dir/keynest-keychain-checks"
"$work_dir/keynest-keychain-checks"
