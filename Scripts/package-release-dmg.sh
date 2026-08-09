#!/bin/bash

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly APP_PATH="${APP_PATH:?APP_PATH is required}"
readonly OUTPUT_PATH="${OUTPUT_PATH:?OUTPUT_PATH is required}"
readonly RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
readonly REPOSITORY="${GITHUB_REPOSITORY:-Sh7ne/Ice}"
readonly SOURCE_URL="https://github.com/$REPOSITORY/tree/$RELEASE_TAG"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
fi

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/IceDMG.XXXXXX")"
mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/IceDMGMount.XXXXXX")"
mounted=0

detach_volume() {
    for delay in 1 2 3; do
        if hdiutil detach -quiet "$mount_dir"; then
            return 0
        fi
        sleep "$delay"
    done
    hdiutil detach -quiet -force "$mount_dir"
}

cleanup() {
    if [[ "$mounted" == 1 ]]; then
        detach_volume || true
    fi
    rm -rf "$staging_dir" "$mount_dir"
}
trap cleanup EXIT

ditto "$APP_PATH" "$staging_dir/Ice.app"
ln -s /Applications "$staging_dir/Applications"
cp "$ROOT_DIR/LICENSE" "$staging_dir/LICENSE"
printf 'Corresponding source: %s\n' "$SOURCE_URL" > "$staging_dir/SOURCE.txt"

codesign --verify --deep --strict --verbose=2 "$staging_dir/Ice.app"

output_dir="$(dirname "$OUTPUT_PATH")"
output_name="$(basename "$OUTPUT_PATH")"
mkdir -p "$output_dir"
rm -f "$OUTPUT_PATH" "$OUTPUT_PATH.sha256"

hdiutil create \
    -quiet \
    -volname Ice \
    -srcfolder "$staging_dir" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$OUTPUT_PATH"
hdiutil verify "$OUTPUT_PATH"

mounted=1
hdiutil attach \
    -quiet \
    -nobrowse \
    -readonly \
    -mountpoint "$mount_dir" \
    "$OUTPUT_PATH"

test -d "$mount_dir/Ice.app"
test "$(readlink "$mount_dir/Applications")" == "/Applications"
cmp "$ROOT_DIR/LICENSE" "$mount_dir/LICENSE"
grep -Fx "Corresponding source: $SOURCE_URL" "$mount_dir/SOURCE.txt"
codesign --verify --deep --strict --verbose=2 "$mount_dir/Ice.app"

detach_volume
mounted=0

(
    cd "$output_dir"
    shasum -a 256 "$output_name" > "$output_name.sha256"
    shasum -a 256 -c "$output_name.sha256"
)

printf 'Packaged DMG: %s\n' "$OUTPUT_PATH"
printf 'Checksum: %s.sha256\n' "$OUTPUT_PATH"
