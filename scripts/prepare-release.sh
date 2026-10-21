#!/bin/bash
# Prepare a signed, notarized Universal app and signed appcast. Does not publish.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${IDEALINE_CODE_SIGN_IDENTITY:?Set the stable Developer ID Application identity}"
: "${IDEALINE_NOTARY_PROFILE:?Set the notarytool Keychain profile}"
: "${IDEALINE_DOWNLOAD_URL_PREFIX:?Set the HTTPS release asset URL prefix ending in /}"
ACCOUNT="${IDEALINE_SPARKLE_ACCOUNT:-idealine}"
export IDEALINE_DISTRIBUTION=1 IDEALINE_UNIVERSAL=1 IDEALINE_OUTPUT_DIR=build/Release
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
python3 scripts/release_config.py --require-updates "$WORK/Info.plist"
python3 - "$IDEALINE_DOWNLOAD_URL_PREFIX" <<'PY'
import sys
from urllib.parse import urlsplit
url = urlsplit(sys.argv[1])
if url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None or url.query or url.fragment or not url.path.endswith('/'):
    sys.exit('Download prefix must be an HTTPS URL ending in /, without credentials, query or fragment.')
PY
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$WORK/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$WORK/Info.plist")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$WORK/Info.plist")"
# Refuse reusing or rolling back a published build number.
python3 - "$BUILD" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
feed = Path('appcast.xml')
if feed.exists():
    root = ET.parse(feed).getroot()
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    versions = [n.text for n in root.iter(ns + 'version')]
    versions += [n.attrib[ns + 'version'] for n in root.iter('enclosure') if ns + 'version' in n.attrib]
    if any(not v or not v.isdecimal() or int(v) >= int(sys.argv[1]) for v in versions):
        sys.exit('Build must be greater than every published appcast version.')
PY
swift package resolve
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
KEYCHAIN_PUBLIC_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
if [[ "$PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]]; then
  echo 'release.json public key does not match the selected Sparkle Keychain account.' >&2
  exit 2
fi
swift test
python3 scripts/test_release_config.py
scripts/build-app.sh
APP="build/Release/灵感晾台.app"
ARCHIVE="IdeaLine-v${VERSION}-macOS-universal.zip"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/IdeaLine")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || { echo 'Missing Universal architecture.' >&2; exit 2; }
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarization.zip"
xcrun notarytool submit "$WORK/notarization.zip" --keychain-profile "$IDEALINE_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
# Archive only after stapling. EdDSA signs these exact bytes.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$ARCHIVE"
if [[ -f appcast.xml ]]; then cp appcast.xml "$WORK/appcast.xml"; fi
if [[ -f "docs/releases/$VERSION.md" ]]; then cp "docs/releases/$VERSION.md" "$WORK/${ARCHIVE%.zip}.md"; fi
rm "$WORK/notarization.zip"
"$TOOLS/generate_appcast" --account "$ACCOUNT" \
  --download-url-prefix "$IDEALINE_DOWNLOAD_URL_PREFIX" \
  --embed-release-notes --maximum-deltas 0 --maximum-versions 10 \
  -o "$WORK/appcast.xml" "$WORK"
python3 - "$WORK/appcast.xml" "$ARCHIVE" "$BUILD" "$IDEALINE_DOWNLOAD_URL_PREFIX" <<'PY'
import base64
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
feed, archive, build, prefix = sys.argv[1:]
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).findall('./channel/item')
matching = [i for i in items if i.findtext(ns + 'version') == build]
if len(matching) != 1:
    sys.exit('Appcast is missing this build.')
enclosure = matching[0].find('enclosure')
if enclosure is None or enclosure.get('url') != prefix + archive:
    sys.exit('Appcast download URL mismatch.')
if len(base64.b64decode(enclosure.get(ns + 'edSignature', ''), validate=True)) != 64:
    sys.exit('Appcast is missing its EdDSA signature.')
if int(enclosure.get('length', '0')) != Path(feed).with_name(archive).stat().st_size:
    sys.exit('Appcast length mismatch.')
PY
cp "$WORK/$ARCHIVE" "build/Release/$ARCHIVE"
cp "$WORK/appcast.xml" build/Release/appcast.xml
printf 'Prepared: build/Release/%s\nAppcast: build/Release/appcast.xml\nUpload the archive before publishing the appcast.\n' "$ARCHIVE"
