#!/bin/zsh
# Copy an already-built app into the separately identified demo application.
# The application creates its own demo vault when launched; this script never
# reads, creates, replaces or deletes any vault or Application Support directory.
set -euo pipefail

project_dir="${0:A:h:h}"
build_root="$project_dir/dist/apps.noindex"
source_app="$build_root/Keynest.app"
demo_app="$build_root/Keynest Demo.app"

for directory in "$project_dir/dist" "$build_root"; do
    if [[ -L "$directory" || ! -d "$directory" ]]; then
        print -u2 "Build apps.noindex/Keynest.app first; the build directory must not be a symbolic link."
        exit 1
    fi
done

if [[ ! -d "$source_app" || -L "$source_app" || ! -f "$source_app/Contents/Info.plist" || ! -x "$source_app/Contents/MacOS/Keynest" ]]; then
    print -u2 "Build dist/apps.noindex/Keynest.app with scripts/build-app.sh before creating the demo app."
    exit 1
fi
if [[ -L "$demo_app" ]]; then
    print -u2 "Refusing to replace a symbolic link at the demo app destination."
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" != local.keynest.mac ]]; then
    print -u2 "The source app is not Keynest."
    exit 1
fi
codesign --verify --deep --strict -R '=identifier "local.keynest.mac"' "$source_app"

# Stage the entire app so a failed edit or signing step cannot leave a partial
# demo bundle in dist. Only the explicitly named generated app is replaced.
stage_dir="$(mktemp -d "$build_root/.demo-app.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
staged_app="$stage_dir/Keynest Demo.app"
ditto "$source_app" "$staged_app"
info_plist="$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.keynest.demo' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Keynest Demo' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Keynest Demo' "$info_plist"
plutil -lint "$info_plist"
codesign --force --sign - --options runtime --identifier local.keynest.demo "$staged_app"
codesign --verify --deep --strict "$staged_app"

if [[ -e "$demo_app" ]]; then
    if [[ ! -d "$demo_app" || "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$demo_app/Contents/Info.plist")" != local.keynest.demo ]]; then
        print -u2 "Refusing to replace an unrecognized generated demo app: $demo_app"
        exit 1
    fi
    rm -rf "$demo_app"
fi
mv "$staged_app" "$demo_app"
print "Built: $demo_app"
print "No vault was created or changed. The demo app initializes its separate fictional library when opened."
print "Use scripts/install-apps.sh to install; do not launch the build copy."
