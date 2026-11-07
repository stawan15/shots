#!/bin/bash
# Build shots and install it into ~/.local/bin.
set -euo pipefail
cd "$(dirname "$0")"

echo "building..."
swift build -c release
swift run -c release shots-selftest

mkdir -p "$HOME/.local/bin"
cp .build/release/shots "$HOME/.local/bin/shots"
echo "installed $HOME/.local/bin/shots"
"$HOME/.local/bin/shots" version
