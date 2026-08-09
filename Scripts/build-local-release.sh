#!/bin/bash

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly CONFIGURATION="${CONFIGURATION:-Release}"
readonly DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/IceLocalDerivedData}"
readonly SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-${TMPDIR:-/tmp}/IceLocalSourcePackages}"
readonly BUILD_ARCHS="${ICE_BUILD_ARCHS:-$(uname -m)}"
readonly DEVELOPMENT_TEAM="${ICE_DEVELOPMENT_TEAM:-AMHB5QVH4B}"
readonly DISTRIBUTION_BUILD="${ICE_DISTRIBUTION_BUILD:-0}"
readonly SIGNING_MODE="${ICE_SIGNING_MODE:-developer}"
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

case "$SIGNING_MODE" in
developer | adhoc)
    ;;
*)
    echo "ICE_SIGNING_MODE must be developer or adhoc" >&2
    exit 1
    ;;
esac

if [[ "$SIGNING_MODE" == "adhoc" && "$DISTRIBUTION_BUILD" == 1 ]]; then
    echo "Ad-hoc builds cannot be used as notarized distribution builds" >&2
    exit 1
fi

case "$DISTRIBUTION_BUILD" in
0)
    code_sign_timestamp_option="--timestamp=none"
    ;;
1)
    code_sign_timestamp_option="--timestamp"
    ;;
*)
    echo "ICE_DISTRIBUTION_BUILD must be 0 or 1" >&2
    exit 1
    ;;
esac
readonly CODE_SIGN_TIMESTAMP_OPTION="$code_sign_timestamp_option"

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    signing_identity="-"
    xcode_development_team=""
    ad_hoc_code_signing_allowed="YES"
else
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

    selected_identity_info="$(
        printf '%s\n' "$valid_identities" |
            awk -v identity="$signing_identity" 'index($0, identity) { print; exit }'
    )"
    if [[ -z "$selected_identity_info" ]]; then
        echo "The requested code-signing identity is not valid" >&2
        exit 1
    fi
    if [[ "$DISTRIBUTION_BUILD" == 1 && "$selected_identity_info" != *'"Developer ID Application:'* ]]; then
        echo "Distribution builds require a Developer ID Application identity" >&2
        exit 1
    fi

    xcode_development_team="$DEVELOPMENT_TEAM"
    ad_hoc_code_signing_allowed="NO"
fi
readonly SIGNING_IDENTITY="$signing_identity"
readonly XCODE_DEVELOPMENT_TEAM="$xcode_development_team"
readonly AD_HOC_CODE_SIGNING_ALLOWED="$ad_hoc_code_signing_allowed"

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
    AD_HOC_CODE_SIGNING_ALLOWED="$AD_HOC_CODE_SIGNING_ALLOWED" \
    DEVELOPMENT_TEAM="$XCODE_DEVELOPMENT_TEAM" \
    ENABLE_HARDENED_RUNTIME=YES \
    ENABLE_DEBUG_DYLIB=NO \
    OTHER_CODE_SIGN_FLAGS="$CODE_SIGN_TIMESTAMP_OPTION" \
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

sign_code() {
    codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        "$CODE_SIGN_TIMESTAMP_OPTION" \
        "$@"
}

# Only Downloader's entitlements are intended to survive Sparkle's ad-hoc signature.
sign_code "$SPARKLE_INSTALLER_PATH"
sign_code --preserve-metadata=entitlements "$SPARKLE_DOWNLOADER_PATH"
sign_code "$SPARKLE_AUTOUPDATE_PATH"
sign_code "$SPARKLE_UPDATER_PATH"
sign_code "$SPARKLE_PATH"
sign_code \
    --preserve-metadata=identifier,entitlements \
    "$MENU_BAR_ITEM_SERVICE_PATH"

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    signing_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/IceAdHocSigning.XXXXXX")"
    trap 'rm -rf "$signing_temp_dir"' EXIT
    entitlements_path="$signing_temp_dir/Ice.entitlements"
    library_constraint_path="$signing_temp_dir/Sparkle.coderequirement"

    plutil -create xml1 "$entitlements_path"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.security.cs.disable-library-validation bool true" \
        "$entitlements_path"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.security.files.user-selected.read-only bool true" \
        "$entitlements_path"

    plutil -create xml1 "$library_constraint_path"
    plutil -insert cdhash -json '{"$in":[]}' "$library_constraint_path"

    index=0
    for architecture in $(lipo -archs "$APP_PATH/Contents/MacOS/Ice"); do
        signature_info="$(codesign -d --arch "$architecture" --verbose=4 "$SPARKLE_PATH" 2>&1)"
        cdhash="$(printf '%s\n' "$signature_info" | sed -n 's/^CDHash=//p')"
        if [[ -z "$cdhash" ]]; then
            echo "Unable to read Sparkle CDHash for $architecture" >&2
            exit 1
        fi
        encoded_hash="$(printf '%s' "$cdhash" | xxd -r -p | base64)"
        plutil \
            -insert "cdhash.\$in.$index" \
            -data "$encoded_hash" \
            "$library_constraint_path"
        index=$((index + 1))
    done

    if [[ "$index" -eq 0 ]]; then
        echo "Sparkle contains no supported architectures" >&2
        exit 1
    fi

    codesign --validate-constraint "$library_constraint_path"
    sign_code \
        --preserve-metadata=identifier \
        --entitlements "$entitlements_path" \
        --library-constraint "$library_constraint_path" \
        "$APP_PATH"
else
    sign_code \
        --preserve-metadata=identifier,entitlements \
        "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

signature_paths=("$APP_PATH" "${embedded_code_paths[@]}")
expected_team="$(
    codesign -d --verbose=4 "$APP_PATH" 2>&1 |
        sed -n 's/^TeamIdentifier=//p'
)"
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    if [[ -n "$expected_team" && "$expected_team" != "not set" ]]; then
        echo "The ad-hoc release unexpectedly has Team ID $expected_team" >&2
        exit 1
    fi
else
    if [[ -z "$expected_team" || "$expected_team" == "not set" ]]; then
        echo "The local release does not have a signing Team ID" >&2
        exit 1
    fi
    if [[ "$expected_team" != "$DEVELOPMENT_TEAM" ]]; then
        echo "The signing identity belongs to Team $expected_team, not $DEVELOPMENT_TEAM" >&2
        echo "Set ICE_DEVELOPMENT_TEAM to the selected identity's Team ID" >&2
        exit 1
    fi
fi

for code_path in "${signature_paths[@]}"; do
    signature_info="$(codesign -d --verbose=4 "$code_path" 2>&1)"
    team="$(printf '%s\n' "$signature_info" | sed -n 's/^TeamIdentifier=//p')"
    if [[ "$SIGNING_MODE" == "adhoc" ]]; then
        if [[ -n "$team" && "$team" != "not set" ]]; then
            echo "$code_path unexpectedly has Team ID $team" >&2
            exit 1
        fi
        if [[ "$signature_info" != *"runtime"* || "$signature_info" != *"Signature=adhoc"* ]]; then
            echo "$code_path is not ad-hoc signed with the hardened runtime" >&2
            exit 1
        fi
    else
        if [[ "$team" != "$expected_team" ]]; then
            echo "$code_path is signed by Team $team instead of $expected_team" >&2
            exit 1
        fi
        if [[ "$signature_info" != *"runtime"* || "$signature_info" == *"Signature=adhoc"* ]]; then
            echo "$code_path is not Developer-signed with the hardened runtime" >&2
            exit 1
        fi
    fi
    if [[ "$DISTRIBUTION_BUILD" == 1 && "$signature_info" != *"Timestamp="* ]]; then
        echo "$code_path does not have a secure signing timestamp" >&2
        exit 1
    fi

    entitlements="$(codesign -d --entitlements - "$code_path" 2>&1)"
    if [[ "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
        echo "$code_path contains unsafe development entitlements" >&2
        exit 1
    fi
    if [[ "$entitlements" == *"com.apple.security.cs.disable-library-validation"* && \
        ( "$SIGNING_MODE" != "adhoc" || "$code_path" != "$APP_PATH" ) ]]; then
        echo "$code_path contains an unexpected library-validation exception" >&2
        exit 1
    fi
    if [[ "$SIGNING_MODE" == "adhoc" && "$code_path" == "$APP_PATH" && \
        "$entitlements" != *"com.apple.security.cs.disable-library-validation"* ]]; then
        echo "$code_path is missing its ad-hoc library-validation exception" >&2
        exit 1
    fi
    if [[ "$code_path" == "$SPARKLE_AUTOUPDATE_PATH" && \
        "$entitlements" == *"com.apple.application-identifier"* ]]; then
        echo "$code_path retained Sparkle's ad-hoc application identifier" >&2
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

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    printf 'Built ad-hoc-signed %s release: %s\n' "$BUILD_ARCHS" "$APP_PATH"
elif [[ "$DISTRIBUTION_BUILD" == 1 ]]; then
    printf 'Built Developer ID-signed %s release: %s\n' "$BUILD_ARCHS" "$APP_PATH"
else
    printf 'Built Developer-signed %s release: %s\n' "$BUILD_ARCHS" "$APP_PATH"
fi
