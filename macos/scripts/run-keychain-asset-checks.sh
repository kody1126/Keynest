#!/bin/bash
# Validate source artwork, or an app's Contents/Resources against source.
# No Blender, SwiftPM build, renderer, window, network, or vault is initialized.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
if (( $# > 1 )); then
    printf 'Usage: %s [Resources directory]\n' "$0" >&2
    exit 2
fi
resources_dir="${1:-$package_dir/Resources}"
if [[ ! -d "$resources_dir" || -L "$resources_dir" ]]; then
    printf 'Resources must be an existing directory, not a symbolic link: %s\n' "$resources_dir" >&2
    exit 2
fi

work_dir="$(mktemp -d /private/tmp/keynest-keychain-asset-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="/private/tmp/keynest-keychain-asset-module-cache"
mkdir -p "$module_cache" "$work_dir/core"
# Compile snapshots of the real Core/catalog and mesh decoder without the App.
cp "$package_dir"/Sources/KeynestCore/*.swift "$work_dir/core/"
cp "$package_dir/Sources/KeynestApp/KeychainMeshAsset.swift" "$work_dir/KeychainMeshAsset.swift"
cp "$script_dir/KeychainAssetChecks.swift" "$work_dir/KeychainAssetChecks.swift"

CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
    "$work_dir"/core/*.swift "$work_dir/KeychainMeshAsset.swift" "$work_dir/KeychainAssetChecks.swift" \
    -o "$work_dir/keynest-keychain-asset-checks"
"$work_dir/keynest-keychain-asset-checks" "$resources_dir" "$package_dir/Resources"
