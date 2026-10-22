#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -parse-as-library -O \
  Sources/IdeaLine/Store.swift Sources/IdeaLine/HotKeys.swift Sources/IdeaLine/Views.swift Sources/IdeaLine/LinePosition.swift \
  scripts/render-readme.swift -o build/render-readme
build/render-readme "${1:-docs/images}"
