#!/bin/bash
set -euo pipefail

# Live macOS 27 test: only the temporary fixture is intentionally hidden.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/IceNativeSmoke.XXXXXX")"
FIXTURE="$TEST_DIR/Ice Native Test Fixture.app"
cleanup() {
    if [[ -n "${fixture_pid:-}" ]]; then
        kill "$fixture_pid" 2>/dev/null || true
        wait "$fixture_pid" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$FIXTURE/Contents/MacOS"
cp "$ROOT_DIR/Tests/NativeMenuBar/FixtureInfo.plist" "$FIXTURE/Contents/Info.plist"
xcrun swiftc "$ROOT_DIR/Tests/NativeMenuBar/Fixture.swift" -o "$FIXTURE/Contents/MacOS/Fixture"
codesign --force --sign - "$FIXTURE"
xcrun clang -fobjc-arc -fmodules -c "$ROOT_DIR/Ice/MenuBar/Native/NativeMenuBarBridge.m" -o "$TEST_DIR/bridge.o"
xcrun swiftc -parse-as-library \
    -import-objc-header "$ROOT_DIR/Ice/MenuBar/Native/NativeMenuBarBridge.h" \
    "$ROOT_DIR/Ice/MenuBar/Native/NativeMenuBarSnapshot.swift" \
    "$ROOT_DIR/Tests/NativeMenuBar/SmokeTest.swift" "$TEST_DIR/bridge.o" \
    -o "$TEST_DIR/SmokeTest"
"$FIXTURE/Contents/MacOS/Fixture" &
fixture_pid=$!
sleep 2
/usr/bin/perl -e 'alarm shift; exec @ARGV' 30 "$TEST_DIR/SmokeTest"
