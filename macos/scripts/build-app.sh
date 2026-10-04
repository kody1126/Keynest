#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
cache_dir="${TMPDIR:-/tmp}/keynest-build-cache"
build_root="$project_dir/dist/apps.noindex"
for directory in "$project_dir/dist" "$build_root"; do
    if [[ -L "$directory" ]]; then
        print -u2 "Refusing a symbolic-link build directory: $directory"
        exit 1
    fi
done
mkdir -p "$cache_dir/clang" "$cache_dir/swift" "$build_root"
export CLANG_MODULE_CACHE_PATH="$cache_dir/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir/swift"
swift build -c release --disable-sandbox
output_app="$build_root/Keynest.app"
if [[ -L "$output_app" ]]; then
    print -u2 "Refusing a symbolic-link app destination: $output_app"
    exit 1
fi
stage_dir="$(mktemp -d "$build_root/.build.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app_dir="$stage_dir/Keynest.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/Keynest "$app_dir/Contents/MacOS/Keynest"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
ditto Resources/ProviderIcons "$app_dir/Contents/Resources/ProviderIcons"
ditto Resources/ToolIcons "$app_dir/Contents/Resources/ToolIcons"
mkdir -p "$app_dir/Contents/Resources/KeychainArt/charms"
cp Resources/KeychainArt/glass-key-v1.mesh.json "$app_dir/Contents/Resources/KeychainArt/"
cp Resources/KeychainArt/manifest.json "$app_dir/Contents/Resources/KeychainArt/"
cp Resources/KeychainArt/charms/*.mesh.json "$app_dir/Contents/Resources/KeychainArt/charms/"
bash "$project_dir/scripts/run-keychain-asset-checks.sh" "$app_dir/Contents/Resources"
selected_icon="$(tr -d '[:space:]' < Resources/AppIcon.selection)"
case "$selected_icon" in
    A|B|C|D) iconset="Resources/design/options/$selected_icon.iconset" ;;
    E|F|G|H) iconset="Resources/design/options-light-ai/$selected_icon.iconset" ;;
    C1|C2|C3|C4) iconset="Resources/design/options-c-palette/$selected_icon.iconset" ;;
    *) print -u2 "Unknown App icon selection: $selected_icon"; exit 1 ;;
esac
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --identifier local.keynest.mac "$app_dir"
codesign --verify --deep --strict "$app_dir"
if [[ -e "$output_app" ]]; then
    if [[ ! -d "$output_app" || "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output_app/Contents/Info.plist")" != local.keynest.mac ]]; then
        print -u2 "Refusing to replace an unrecognized generated app: $output_app"
        exit 1
    fi
    rm -rf "$output_app"
fi
mv "$app_dir" "$output_app"
print "Built: $output_app"
print "App icon: $selected_icon (all candidate resources preserved)"
print "Use scripts/install-apps.sh to install; do not launch the build copy."
