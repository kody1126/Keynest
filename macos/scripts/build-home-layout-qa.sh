#!/bin/bash
# Creates only a temporary test-only app; never launches or installs it.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
qa_root="$(mktemp -d /private/tmp/keynest-live-layout-qa.XXXXXX)"
mv "$qa_root" "$qa_root.noindex"
qa_root="$qa_root.noindex"
mkdir -p "$qa_root/src/Core" "$qa_root/build"
module_cache=/private/tmp/keynest-home-layout-qa-module-cache
mkdir -p "$module_cache"
for source in Model HomeCatalog KeychainConfiguration ProviderPreset; do
    cp "$package_dir/Sources/KeynestCore/$source.swift" "$qa_root/src/Core/"
done
for source in HomeCardLayout HomeLayoutReorder HomeLayoutEditing HomeCardPresentation ProviderPicker; do
    cp "$package_dir/Sources/KeynestApp/$source.swift" "$qa_root/src/"
done
cp "$script_dir/HomeLayoutVisualQA.swift" "$qa_root/src/"
app="$qa_root/Keynest Live Layout QA.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$package_dir/Resources/ProviderIcons" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.keynest.layout-visual-qa</string><key>CFBundleExecutable</key><string>KeynestLayoutQA</string><key>CFBundleName</key><string>Keynest Live Layout QA</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
xcrun swiftc -swift-version 5 -strict-concurrency=complete -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
  -emit-library -static -emit-module -module-name KeynestCore -emit-module-path "$qa_root/build/KeynestCore.swiftmodule" \
  "$qa_root"/src/Core/*.swift -o "$qa_root/build/libKeynestCore.a"
xcrun swiftc -swift-version 5 -strict-concurrency=complete -parse-as-library -D KEYNEST_HOME_LAYOUT_QA \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$module_cache" \
  -I "$qa_root/build" -L "$qa_root/build" -lKeynestCore "$qa_root"/src/*.swift \
  -o "$app/Contents/MacOS/KeynestLayoutQA"
codesign --force --sign - --options runtime --identifier local.keynest.layout-visual-qa "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
