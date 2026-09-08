#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haut-ui-smoke.XXXXXX")"
trap 'rm -r "$BUILD_DIR"' EXIT

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

"$SWIFTC" \
    -o "$BUILD_DIR/macos_ui_smoke_tests" \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx11.0 \
    -framework Cocoa \
    -framework UserNotifications \
    -framework Network \
    -framework Security \
    -framework LocalAuthentication \
    "$PROJECT_DIR/Sources/AppRuntime.swift" \
    "$PROJECT_DIR/Sources/Logger.swift" \
    "$PROJECT_DIR/Sources/Config.swift" \
    "$PROJECT_DIR/Sources/Encryption.swift" \
    "$PROJECT_DIR/Sources/SrunProtocol.swift" \
    "$PROJECT_DIR/Sources/SessionPolicy.swift" \
    "$PROJECT_DIR/Sources/SingleInstanceGuard.swift" \
    "$PROJECT_DIR/Sources/DirectHTTPClient.swift" \
    "$PROJECT_DIR/Sources/SrunAPI.swift" \
    "$PROJECT_DIR/Sources/UpdateChecker.swift" \
    "$PROJECT_DIR/Sources/UpdateWindow.swift" \
    "$PROJECT_DIR/Sources/SettingsWindow.swift" \
    "$PROJECT_DIR/Sources/AboutWindow.swift" \
    "$PROJECT_DIR/Sources/LaunchManager.swift" \
    "$PROJECT_DIR/Sources/StatusBarController.swift" \
    "$PROJECT_DIR/tests/ControllerSessionTests.swift" \
    "$PROJECT_DIR/tests/UISmokeTests.swift"

"$BUILD_DIR/macos_ui_smoke_tests" --ui-smoke-test
