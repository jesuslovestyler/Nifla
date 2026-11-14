#!/bin/sh
# Build the Nifla interpreter into ./nifla
#
# Uses swiftc directly — no package manager needed. Set SWIFTC to point
# at a specific swiftc if the automatic search doesn't find yours.

set -e
cd "$(dirname "$0")"

SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if command -v swiftc >/dev/null 2>&1; then
        SWIFTC="$(command -v swiftc)"
    elif [ -x /opt/swift/usr/bin/swiftc ]; then
        SWIFTC=/opt/swift/usr/bin/swiftc
    elif [ -x "$HOME/swift/usr/bin/swiftc" ]; then
        SWIFTC="$HOME/swift/usr/bin/swiftc"
    elif [ -x "$HOME/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        # The toolchain the Cardnull OS builds use in this workspace.
        SWIFTC="$HOME/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc"
    else
        echo "build.sh: no swiftc found (set SWIFTC=/path/to/swiftc)" >&2
        exit 1
    fi
fi

"$SWIFTC" src/*.swift -o nifla
echo "Built ./nifla"
