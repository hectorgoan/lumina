#!/bin/bash
# Renders the hero and social images in docs/marketing from the app's real
# views: compiles Lumina's sources (minus its @main) with
# scripts/marketing/main.swift into a small renderer and runs it.
# It turns on Caffeine and Stay Green while it runs and samples the system
# monitor for about 45 seconds, so the CPU graph has history.
# Usage: scripts/render-marketing.sh
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release > /dev/null
FRAMEWORKS="$(swift build -c release --show-bin-path)"
RENDERER="$(mktemp -d)/render"

find Sources/Lumina -name "*.swift" ! -name "LuminaApp.swift" -print0 \
    | xargs -0 swiftc -O -swift-version 6 -module-name LuminaRender scripts/marketing/main.swift \
        -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" -o "$RENDERER"

"$RENDERER" docs/marketing
