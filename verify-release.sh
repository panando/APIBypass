#!/bin/bash
set -euo pipefail

APP_PATH="${1:-APIBypass.app}"
EXECUTABLE="$APP_PATH/Contents/MacOS/APIBypass"
EXPECTED_GATEKEEPER_FAILURES=(
    "Adhoc Signed App"
    "Notary Ticket Missing"
)

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH" >&2
    exit 1
fi

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: executable not found: $EXECUTABLE" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=4 "$APP_PATH"

if otool -L "$EXECUTABLE" | grep -q '/Applications/Xcode.app/'; then
    echo "error: executable references Xcode toolchain libraries" >&2
    otool -L "$EXECUTABLE" >&2
    exit 1
fi

if otool -l "$EXECUTABLE" | grep -q '/Applications/Xcode.app/'; then
    echo "error: executable contains Xcode toolchain load paths" >&2
    otool -l "$EXECUTABLE" >&2
    exit 1
fi

GATEKEEPER_OUTPUT=$(mktemp)
if syspolicy_check distribution "$APP_PATH" >"$GATEKEEPER_OUTPUT" 2>&1; then
    rm -f "$GATEKEEPER_OUTPUT"
    exit 0
fi

for expected in "${EXPECTED_GATEKEEPER_FAILURES[@]}"; do
    if ! grep -q "$expected" "$GATEKEEPER_OUTPUT"; then
        cat "$GATEKEEPER_OUTPUT" >&2
        rm -f "$GATEKEEPER_OUTPUT"
        exit 1
    fi
done

if grep -q "Codesign Error\|Bad Load Command" "$GATEKEEPER_OUTPUT"; then
    cat "$GATEKEEPER_OUTPUT" >&2
    rm -f "$GATEKEEPER_OUTPUT"
    exit 1
fi

rm -f "$GATEKEEPER_OUTPUT"
echo "Gatekeeper distribution check has only expected no-certificate failures."
