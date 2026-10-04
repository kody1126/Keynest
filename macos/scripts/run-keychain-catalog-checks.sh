#!/bin/bash
# Pure catalog checks with in-memory fictional entries. No SwiftPM, AppModel,
# windows, network, clipboard, normal vault paths, or hardware authentication.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-keychain-catalog-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="/private/tmp/keynest-keychain-catalog-module-cache"
mkdir -p "$module_cache" "$work_dir/core"

# Snapshot production sources so a concurrent app build cannot change this run.
cp "$package_dir"/Sources/KeynestCore/*.swift "$work_dir/core/"
cp "$script_dir/KeychainCatalogChecks.swift" "$work_dir/KeychainCatalogChecks.swift"
python3 - "$package_dir/Sources/KeynestApp/KeychainCatalog.swift" "$work_dir/KeychainCatalog.swift" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
pathlib.Path(sys.argv[2]).write_text(source.replace("import KeynestCore\n", "// Core sources compiled in this same module.\n"), encoding="utf-8")
PY

CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
    "$work_dir"/core/*.swift "$work_dir/KeychainCatalog.swift" "$work_dir/KeychainCatalogChecks.swift" \
    -o "$work_dir/keynest-keychain-catalog-checks"
"$work_dir/keynest-keychain-catalog-checks"
