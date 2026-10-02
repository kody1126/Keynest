#!/bin/zsh
# Install only this project's two apps. Never launch them, access their vaults,
# change indexing settings, or modify any other installed application.
set -euo pipefail

project_dir="${0:A:h:h}"
build_root="$project_dir/dist/apps.noindex"
install_root="$HOME/Applications"
backup_root="$project_dir/.build/app-backups"
app_names=("Keynest.app" "Keynest Demo.app")
bundle_ids=("local.keynest.mac" "local.keynest.demo")

fail() { print -u2 -- "$1"; exit 1; }
check_directory() {
    [[ ! -L "$1" ]] || fail "Refusing a symbolic-link directory: $1"
    [[ ! -e "$1" || -d "$1" ]] || fail "Expected a directory: $1"
}
verify_app() {
    local app_path="$1" expected_id="$2"
    [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
    [[ -z "$(/usr/bin/find "$app_path" -type l -print -quit)" ]] || return 1
    [[ -f "$app_path/Contents/Info.plist" && -x "$app_path/Contents/MacOS/Keynest" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")" == "$expected_id" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")" == Keynest ]] || return 1
    /usr/bin/codesign --verify --deep --strict -R "=identifier \"$expected_id\"" "$app_path"
}

for directory in "$project_dir/dist" "$build_root" "$project_dir/.build" "$backup_root" "$install_root"; do
    check_directory "$directory"
done
[[ -d "$build_root" ]] || fail "Run scripts/package-app.sh or both build scripts first."

# Preflight both sides before creating backups or changing either installed app.
for app_index in 1 2; do
    source_app="$build_root/${app_names[$app_index]}"
    target_app="$install_root/${app_names[$app_index]}"
    verify_app "$source_app" "${bundle_ids[$app_index]}" || fail "Invalid source app or signature: $source_app"
    if [[ -e "$target_app" || -L "$target_app" ]]; then
        verify_app "$target_app" "${bundle_ids[$app_index]}" || fail "Refusing to replace an unrecognized app or symbolic link: $target_app"
        if /usr/sbin/lsof -t "$target_app/Contents/MacOS/Keynest" >/dev/null 2>&1; then
            fail "Close ${app_names[$app_index]} before installing. No app was replaced."
        fi
    fi
done

mkdir -p "$install_root" "$backup_root"
install_token="$(/bin/date -u '+%Y%m%dT%H%M%SZ')-$(/usr/bin/uuidgen)"
stage_dir="$install_root/.keynest-install-$install_token.noindex"
mkdir -m 700 "$stage_dir"
mkdir "$stage_dir/new" "$stage_dir/previous" "$stage_dir/verified-backups"
old_moved=(0 0)
new_installed=(0 0)
installation_complete=0

finish() {
    local result="$1" rollback_failed=0 rollback_index target_app previous_app
    if (( ! installation_complete )); then
        for rollback_index in 2 1; do
            target_app="$install_root/${app_names[$rollback_index]}"
            previous_app="$stage_dir/previous/${app_names[$rollback_index]}"
            if (( new_installed[$rollback_index] )); then
                if verify_app "$target_app" "${bundle_ids[$rollback_index]}"; then
                    rm -rf "$target_app" || rollback_failed=1
                else
                    print -u2 "An installed app changed unexpectedly; it was not removed: $target_app"
                    rollback_failed=1
                fi
            fi
            if (( old_moved[$rollback_index] )); then
                if [[ ! -e "$target_app" && ! -L "$target_app" ]]; then
                    mv "$previous_app" "$target_app" || rollback_failed=1
                else
                    rollback_failed=1
                fi
            fi
        done
    fi
    if (( rollback_failed )); then
        print -u2 "Automatic rollback needs attention. Recovery apps: $stage_dir/previous"
        print -u2 "Verified zip backups remain in: $backup_root"
        return 1
    fi
    rm -rf "$stage_dir"
    return "$result"
}
trap 'finish $?' EXIT

# Every prior app gets a portable zip, followed by an extraction and identity /
# signature check. Keep only verified archives; no vault path is involved.
for app_index in 1 2; do
    app_name="${app_names[$app_index]}"
    expected_id="${bundle_ids[$app_index]}"
    source_app="$build_root/$app_name"
    target_app="$install_root/$app_name"
    /usr/bin/ditto "$source_app" "$stage_dir/new/$app_name"
    verify_app "$stage_dir/new/$app_name" "$expected_id" || fail "Staged app verification failed: $app_name"
    if [[ -e "$target_app" ]]; then
        archive_name="$(/bin/date -u '+%Y%m%dT%H%M%SZ')-$(/usr/bin/uuidgen).zip"
        archive_file="$backup_root/$archive_name"
        [[ ! -e "$archive_file" && ! -L "$archive_file" ]] || fail "Backup destination already exists: $archive_file"
        partial_archive="$stage_dir/$archive_name.partial"
        /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$target_app" "$partial_archive"
        /usr/bin/unzip -tq "$partial_archive"
        restore_dir="$stage_dir/verified-backups/$app_index"
        mkdir "$restore_dir"
        /usr/bin/ditto -x -k "$partial_archive" "$restore_dir"
        verify_app "$restore_dir/$app_name" "$expected_id" || fail "Backup verification failed: $app_name"
        /usr/bin/diff -rq "$target_app" "$restore_dir/$app_name" >/dev/null || fail "Backup content differs from the installed app: $app_name"
        mv "$partial_archive" "$archive_file"
        print "Verified backup for $app_name: $archive_file"
    fi
done

for app_index in 1 2; do
    app_name="${app_names[$app_index]}"
    target_app="$install_root/$app_name"
    if [[ -e "$target_app" ]]; then
        # Recheck immediately before the first mutation.
        verify_app "$target_app" "${bundle_ids[$app_index]}" || fail "Installed app changed during preparation: $app_name"
        if /usr/sbin/lsof -t "$target_app/Contents/MacOS/Keynest" >/dev/null 2>&1; then
            fail "Close $app_name before installing. Previous replacements will be rolled back."
        fi
        mv "$target_app" "$stage_dir/previous/$app_name"
        old_moved[$app_index]=1
    elif [[ -L "$target_app" ]]; then
        fail "A symbolic link appeared at the install destination: $target_app"
    fi
    mv "$stage_dir/new/$app_name" "$target_app"
    new_installed[$app_index]=1
    verify_app "$target_app" "${bundle_ids[$app_index]}" || fail "Installed app verification failed: $app_name"
done

installation_complete=1
print "Installed: $install_root/Keynest.app"
print "Installed: $install_root/Keynest Demo.app"
print "Apps were not launched. No vault or system indexing setting was changed."
