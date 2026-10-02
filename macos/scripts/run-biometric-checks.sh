#!/bin/bash
# Real hardware/backend checks with fake temporary data only. No unlockData()
# call, no authentication UI, no ordinary vault or Keychain item access.
# Run in the logged-in user's normal session: an execution sandbox can make
# Secure Enclave/LocalAuthentication unavailable and correctly fail this check.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-biometric-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="${KEYNEST_CHECK_MODULE_CACHE:-/private/tmp/keynest-check-module-cache}"
mkdir -p "$module_cache"
cp "$package_dir/Sources/KeynestApp/BiometricVaultAccess.swift" "$work_dir/BiometricVaultAccess.swift"
cp "$script_dir/BiometricChecks.swift" "$work_dir/BiometricChecks.swift"

CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
    "$work_dir/BiometricVaultAccess.swift" "$work_dir/BiometricChecks.swift" \
    -o "$work_dir/keynest-biometric-checks"
codesign --force --sign - --identifier local.keynest.biometric-checks "$work_dir/keynest-biometric-checks"
"$work_dir/keynest-biometric-checks" "$@"
