#!/bin/bash
# Pure geometry checks with the production mesh decoder and bundled artwork.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-attachment-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/module-cache"
cp "$package_dir/Sources/KeynestApp/KeychainMeshAsset.swift" "$work_dir/KeychainMeshAsset.swift"
cp "$script_dir/KeychainAttachmentChecks.swift" "$work_dir/KeychainAttachmentChecks.swift"
CLANG_MODULE_CACHE_PATH="$work_dir/module-cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$work_dir/module-cache" \
    "$work_dir/KeychainMeshAsset.swift" "$work_dir/KeychainAttachmentChecks.swift" \
    -o "$work_dir/checks"
"$work_dir/checks" "$package_dir/Resources"
