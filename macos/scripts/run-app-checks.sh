#!/bin/bash
# Exercise the real AppModel with fake data in a mandatory temporary vault.
# No SwiftPM, network requests, clipboard use, panels, or normal vault paths.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-app-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="/private/tmp/keynest-app-check-module-cache"
mkdir -p "$module_cache" "$work_dir/core" "$work_dir/vault"

# Snapshot inputs so an independent app build/editor cannot change sources
# midway through swiftc. AppModel's only adaptation removes its module import.
cp "$package_dir"/Sources/KeynestCore/*.swift "$work_dir/core/"
cp "$script_dir/AppModelChecks.swift" "$work_dir/AppModelChecks.swift"
python3 - "$package_dir/Sources/KeynestApp" "$work_dir" <<'PY'
import pathlib
import sys
for name in ["AppModel.swift", "BiometricVaultAccess.swift", "SensitiveClipboard.swift"]:
    source = (pathlib.Path(sys.argv[1]) / name).read_text(encoding="utf-8")
    (pathlib.Path(sys.argv[2]) / name).write_text(source.replace("import KeynestCore\n", "// Core sources compiled in this same module.\n"), encoding="utf-8")
PY

CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
    "$work_dir"/core/*.swift "$work_dir/AppModel.swift" "$work_dir/BiometricVaultAccess.swift" "$work_dir/SensitiveClipboard.swift" "$work_dir/AppModelChecks.swift" \
    -o "$work_dir/keynest-app-checks"
"$work_dir/keynest-app-checks" --test-data-directory "$work_dir/vault"
