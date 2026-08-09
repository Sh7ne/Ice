#!/bin/bash

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly SMOKE_DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/IceLocalDerivedData}"
readonly SMOKE_CONFIGURATION="${CONFIGURATION:-Release}"
readonly APP_PATH="$SMOKE_DERIVED_DATA_PATH/Build/Products/$SMOKE_CONFIGURATION/Ice.app"
readonly TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/IceXPCSmokeHome.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

CONFIGURATION="$SMOKE_CONFIGURATION" \
DERIVED_DATA_PATH="$SMOKE_DERIVED_DATA_PATH" \
"$ROOT_DIR/Scripts/build-local-release.sh"

output="$(
    /usr/bin/perl -e 'alarm shift; exec @ARGV' 15 \
        /usr/bin/env \
        HOME="$TEST_HOME" \
        CFFIXED_USER_HOME="$TEST_HOME" \
        ICE_XPC_SMOKE_TEST=1 \
        "$APP_PATH/Contents/MacOS/Ice"
)"
printf '%s\n' "$output"

if [[ "$output" == *"XPC_SMOKE_TEST_PASS"* ]]; then
    exit 0
fi

if [[ "$output" == *"XPC_SMOKE_TEST_SKIP_UNSUPPORTED_OS"* ]]; then
    exit 0
fi

echo "MenuBarItemService round trip failed" >&2
exit 1
