#!/bin/bash

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly CONFIGURATION="${CONFIGURATION:-Release}"
readonly DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/IceLocalDerivedData}"
readonly SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-${TMPDIR:-/tmp}/IceLocalSourcePackages}"
readonly BUILD_ARCHS="${ICE_BUILD_ARCHS:-$(uname -m)}"
readonly DEVELOPMENT_TEAM="${ICE_DEVELOPMENT_TEAM:-AMHB5QVH4B}"
readonly APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Ice.app"
readonly MENU_BAR_ITEM_SERVICE_PATH="$APP_PATH/Contents/XPCServices/MenuBarItemService.xpc"
readonly SPARKLE_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"
readonly SPARKLE_VERSION_PATH="$SPARKLE_PATH/Versions/Current"
readonly SPARKLE_AUTOUPDATE_PATH="$SPARKLE_VERSION_PATH/Autoupdate"
readonly SPARKLE_UPDATER_PATH="$SPARKLE_VERSION_PATH/Updater.app"
readonly SPARKLE_DOWNLOADER_PATH="$SPARKLE_VERSION_PATH/XPCServices/Downloader.xpc"
readonly SPARKLE_INSTALLER_PATH="$SPARKLE_VERSION_PATH/XPCServices/Installer.xpc"

if [[ "$BUILD_ARCHS" == *[[:space:]]* ]]; then
    echo "Local releases require exactly one architecture" >&2
    exit 1
fi

valid_identities="$(security find-identity -v -p codesigning)"
if [[ -n "${ICE_CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$ICE_CODE_SIGN_IDENTITY"
else
    signing_identity="$(
        printf '%s\n' "$valid_identities" |
            awk '/"Apple Development:/ { print $2; exit }'
    )"
    if [[ -z "$signing_identity" ]]; then
        signing_identity="$(
            printf '%s\n' "$valid_identities" |
                awk '/"Developer ID Application:/ { print $2; exit }'
        )"
    fi
fi

if [[ -z "$signing_identity" ]]; then
    echo "No valid Apple Development or Developer ID Application identity found" >&2
    exit 1
fi
readonly SIGNING_IDENTITY="$signing_identity"

xcodebuild -quiet \
    -project "$ROOT_DIR/Ice.xcodeproj" \
    -scheme Ice \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    ENABLE_HARDENED_RUNTIME=YES \
    ENABLE_DEBUG_DYLIB=NO \
    OTHER_CODE_SIGN_FLAGS=--timestamp=none \
    ARCHS="$BUILD_ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    build

readonly SPARKLE_BINARY_PATH="$SPARKLE_VERSION_PATH/Sparkle"
readonly SPARKLE_UPDATER_BINARY_PATH="$SPARKLE_UPDATER_PATH/Contents/MacOS/Updater"
readonly SPARKLE_DOWNLOADER_BINARY_PATH="$SPARKLE_DOWNLOADER_PATH/Contents/MacOS/Downloader"
readonly SPARKLE_INSTALLER_BINARY_PATH="$SPARKLE_INSTALLER_PATH/Contents/MacOS/Installer"

mach_o_paths=(
    "$APP_PATH/Contents/MacOS/Ice"
    "$MENU_BAR_ITEM_SERVICE_PATH/Contents/MacOS/MenuBarItemService"
    "$SPARKLE_BINARY_PATH"
    "$SPARKLE_AUTOUPDATE_PATH"
    "$SPARKLE_UPDATER_BINARY_PATH"
    "$SPARKLE_DOWNLOADER_BINARY_PATH"
    "$SPARKLE_INSTALLER_BINARY_PATH"
)

for binary_path in "${mach_o_paths[@]}"; do
    architectures="$(lipo -archs "$binary_path")"
    if [[ " $architectures " != *" $BUILD_ARCHS "* ]]; then
        echo "$binary_path does not contain the $BUILD_ARCHS architecture" >&2
        exit 1
    fi
    if [[ "$architectures" != "$BUILD_ARCHS" ]]; then
        thin_path="$(mktemp "$binary_path.thin.XXXXXX")"
        mode="$(stat -f '%Lp' "$binary_path")"
        lipo "$binary_path" -thin "$BUILD_ARCHS" -output "$thin_path"
        chmod "$mode" "$thin_path"
        mv "$thin_path" "$binary_path"
    fi
done

embedded_code_paths=(
    "$SPARKLE_AUTOUPDATE_PATH"
    "$SPARKLE_UPDATER_PATH"
    "$SPARKLE_DOWNLOADER_PATH"
    "$SPARKLE_INSTALLER_PATH"
    "$SPARKLE_PATH"
    "$MENU_BAR_ITEM_SERVICE_PATH"
)

for code_path in "${embedded_code_paths[@]}"; do
    codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp=none \
        --preserve-metadata=identifier,entitlements \
        "$code_path"
done

codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

signature_paths=("$APP_PATH" "${embedded_code_paths[@]}")
expected_team="$(
    codesign -d --verbose=4 "$APP_PATH" 2>&1 |
        sed -n 's/^TeamIdentifier=//p'
)"
if [[ -z "$expected_team" || "$expected_team" == "not set" ]]; then
    echo "The local release does not have a signing Team ID" >&2
    exit 1
fi
if [[ "$expected_team" != "$DEVELOPMENT_TEAM" ]]; then
    echo "The signing identity belongs to Team $expected_team, not $DEVELOPMENT_TEAM" >&2
    echo "Set ICE_DEVELOPMENT_TEAM to the selected identity's Team ID" >&2
    exit 1
fi

for code_path in "${signature_paths[@]}"; do
    signature_info="$(codesign -d --verbose=4 "$code_path" 2>&1)"
    team="$(printf '%s\n' "$signature_info" | sed -n 's/^TeamIdentifier=//p')"
    if [[ "$team" != "$expected_team" ]]; then
        echo "$code_path is signed by Team $team instead of $expected_team" >&2
        exit 1
    fi
    if [[ "$signature_info" != *"runtime"* || "$signature_info" == *"Signature=adhoc"* ]]; then
        echo "$code_path is not Developer-signed with the hardened runtime" >&2
        exit 1
    fi

    entitlements="$(codesign -d --entitlements - "$code_path" 2>&1)"
    if [[ "$entitlements" == *"com.apple.security.cs.disable-library-validation"* || \
        "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
        echo "$code_path contains unsafe development entitlements" >&2
        exit 1
    fi
done

for binary_path in "${mach_o_paths[@]}"; do
    architectures="$(lipo -archs "$binary_path")"
    if [[ "$architectures" != "$BUILD_ARCHS" ]]; then
        echo "$binary_path still contains non-$BUILD_ARCHS code" >&2
        exit 1
    fi
done

printf 'Built Developer-signed %s release: %s\n' "$BUILD_ARCHS" "$APP_PATH"
