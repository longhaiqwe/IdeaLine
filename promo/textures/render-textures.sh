#!/bin/bash
# Build the promo texture renderer against the app sources and write PNGs to promo/build/textures.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p promo/build
swiftc -parse-as-library -O \
  Sources/IdeaLine/Store.swift Sources/IdeaLine/HotKeys.swift Sources/IdeaLine/Views.swift Sources/IdeaLine/LinePosition.swift \
  promo/textures/PromoTextures.swift -o promo/build/promo-textures
promo/build/promo-textures promo/content.json promo/build/textures
