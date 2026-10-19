#!/bin/zsh
# Inspect a public DMG without launching its app or reading any user data.
set -euo pipefail

if (( $# != 1 )); then
    print -u2 "Usage: scripts/verify-release-package.sh <Keynest.dmg>"
    exit 1
fi
image_path="${1:A}"
[[ -f "$image_path" ]] || { print -u2 "Disk image not found: $image_path"; exit 1; }
hdiutil verify "$image_path"
mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/keynest-release-check.XXXXXX")"
mounted=0
cleanup() {
    local result="$1"
    if (( mounted )) && ! hdiutil detach "$mount_dir" >/dev/null; then
        print -u2 "Could not unmount the release check volume: $mount_dir"
        exit 1
    fi
    rmdir "$mount_dir" || exit 1
    exit "$result"
}
trap 'cleanup $?' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$image_path" >/dev/null
mounted=1

# Count every app, including nested bundles, so a leftover Demo cannot ship.
apps=("$mount_dir"/**/*.app(ND))
if (( ${#apps} != 1 )) || [[ "${apps[1]:-}" != "$mount_dir/Keynest.app" ]]; then
    print -u2 "Release packages must contain exactly one app: Keynest.app."
    exit 1
fi
app_path="$mount_dir/Keynest.app"
[[ -d "$app_path" && ! -L "$app_path" ]] || exit 1
info_plist="$app_path/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" == local.keynest.mac ]] || {
    print -u2 "The release app must use the regular Keynest bundle identifier."
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")" == Keynest ]] || exit 1
codesign --verify --deep --strict -R '=identifier "local.keynest.mac"' "$app_path"
print "Verified regular-app-only package: ${image_path:t}"
