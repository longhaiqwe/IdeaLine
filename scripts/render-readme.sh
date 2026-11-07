#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
ditto Sources/IdeaLine/Resources/Paper build/IdeaLine_IdeaLine.bundle/Paper
swiftc -parse-as-library -O \
  Sources/IdeaLine/Store.swift Sources/IdeaLine/HotKeys.swift Sources/IdeaLine/Views.swift Sources/IdeaLine/LinePosition.swift Sources/IdeaLine/Appearance.swift Sources/IdeaLine/PaperTexture.swift \
  scripts/render-readme.swift -o build/render-readme
build/render-readme "${1:-docs/images}" "${2:-}"
