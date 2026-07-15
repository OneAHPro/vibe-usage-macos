#!/bin/bash
set -euo pipefail

DEVELOPER_DIR="$(xcode-select -p)"
TESTING_FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
TESTING_LIBRARIES="$DEVELOPER_DIR/Library/Developer/usr/lib"

if [ -d "$TESTING_FRAMEWORKS/Testing.framework" ]; then
    export DYLD_FRAMEWORK_PATH="$TESTING_FRAMEWORKS${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
    export DYLD_LIBRARY_PATH="$TESTING_LIBRARIES${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    exec swift test \
        -Xswiftc -F \
        -Xswiftc "$TESTING_FRAMEWORKS" \
        -Xlinker -F \
        -Xlinker "$TESTING_FRAMEWORKS" \
        "$@"
fi

exec swift test "$@"
