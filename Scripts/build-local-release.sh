#!/bin/bash

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly CONFIGURATION="${CONFIGURATION:-Release}"
readonly DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/IceLocalDerivedData}"
readonly SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-${TMPDIR:-/tmp}/IceLocalSourcePackages}"
readonly BUILD_ARCHS="${ICE_BUILD_ARCHS:-$(uname -m)}"
readonly APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Ice.app"
readonly MENU_BAR_ITEM_SERVICE_PATH="$APP_PATH/Contents/XPCServices/MenuBarItemService.xpc"
readonly SPARKLE_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"

xcodebuild -quiet \
    -project "$ROOT_DIR/Ice.xcodeproj" \
    -scheme Ice \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    DEVELOPMENT_TEAM= \
    ENABLE_DEBUG_DYLIB=NO \
    ARCHS="$BUILD_ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    build

readonly SIGNING_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/IceLocalSigning.XXXXXX")"
trap 'rm -rf "$SIGNING_TEMP_DIR"' EXIT

readonly ENTITLEMENTS_PATH="$SIGNING_TEMP_DIR/Ice.entitlements"
readonly LIBRARY_CONSTRAINT_PATH="$SIGNING_TEMP_DIR/Sparkle.coderequirement"

# Xcode omits the hardened-runtime flag for ad-hoc target signatures. Restore
# it on the embedded service before sealing its final hash into the main app.
codesign \
    --force \
    --sign - \
    --options runtime \
    --timestamp=none \
    "$MENU_BAR_ITEM_SERVICE_PATH"

# Ad-hoc signatures have no Team ID, so the hardened runtime cannot apply its
# default same-team rule to Sparkle. Keep the exception narrow by allowlisting
# the exact Code Directory hashes of every architecture in the pinned binary.
plutil -create xml1 "$ENTITLEMENTS_PATH"
/usr/libexec/PlistBuddy \
    -c "Add :com.apple.security.cs.disable-library-validation bool true" \
    "$ENTITLEMENTS_PATH"
/usr/libexec/PlistBuddy \
    -c "Add :com.apple.security.files.user-selected.read-only bool true" \
    "$ENTITLEMENTS_PATH"

plutil -create xml1 "$LIBRARY_CONSTRAINT_PATH"
plutil -insert cdhash -json '{"$in":[]}' "$LIBRARY_CONSTRAINT_PATH"

index=0
for architecture in $(lipo -archs "$APP_PATH/Contents/MacOS/Ice"); do
    signature_info="$(codesign -d --arch "$architecture" --verbose=4 "$SPARKLE_PATH" 2>&1)"
    cdhash="$(printf '%s\n' "$signature_info" | sed -n 's/^CDHash=//p')"
    if [[ -z "$cdhash" ]]; then
        echo "Unable to read Sparkle CDHash for $architecture" >&2
        exit 1
    fi
    encoded_hash="$(printf '%s' "$cdhash" | xxd -r -p | base64)"
    plutil -insert "cdhash.\$in.$index" -data "$encoded_hash" "$LIBRARY_CONSTRAINT_PATH"
    index=$((index + 1))
done

if [[ "$index" -eq 0 ]]; then
    echo "Sparkle contains no supported architectures" >&2
    exit 1
fi

codesign --validate-constraint "$LIBRARY_CONSTRAINT_PATH"
codesign \
    --force \
    --sign - \
    --options runtime \
    --timestamp=none \
    --entitlements "$ENTITLEMENTS_PATH" \
    --library-constraint "$LIBRARY_CONSTRAINT_PATH" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

printf 'Built local release: %s\n' "$APP_PATH"
