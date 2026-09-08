#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haut-smoke.XXXXXX")"
trap 'rm -r "$BUILD_DIR"' EXIT
VERSION="$(cat "$PROJECT_DIR/../VERSION")"
printf 'enum BuildVersion { static let value = "%s" }\n' "$VERSION" > "$BUILD_DIR/GeneratedVersion.swift"

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
"$SWIFTC" \
    -sdk "$SDK_PATH" \
    -o "$BUILD_DIR/macos_smoke_tests" \
    -framework Security \
    -framework LocalAuthentication \
    "$BUILD_DIR/GeneratedVersion.swift" \
    "$PROJECT_DIR/Sources/Logger.swift" \
    "$PROJECT_DIR/Sources/Config.swift" \
    "$PROJECT_DIR/Sources/Encryption.swift" \
    "$PROJECT_DIR/Sources/SrunProtocol.swift" \
    "$PROJECT_DIR/tests/CredentialTests.swift" \
    "$PROJECT_DIR/tests/SmokeTests.swift"

"$BUILD_DIR/macos_smoke_tests"
