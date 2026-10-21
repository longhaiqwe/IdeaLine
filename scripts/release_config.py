#!/usr/bin/env python3
"""Validate public release settings and write the app's Info.plist."""
import argparse
import base64
import binascii
import json
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit


def bundle_info(config, require_updates=False):
    version, build = config["version"], config["build"]
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("version must have the form 1.1.0")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("build must be a positive integer string and increase for every release")
    feed, key = config.get("feed_url", ""), config.get("public_ed_key", "")
    if require_updates or feed or key:
        url = urlsplit(feed)
        if url.scheme != "https" or not url.hostname or url.username is not None or url.password is not None:
            raise ValueError("feed_url must be a complete HTTPS URL without credentials")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 32
        except (ValueError, binascii.Error):
            valid_key = False
        if not valid_key:
            raise ValueError("public_ed_key must be a base64-encoded 32-byte Ed25519 public key")
    info = {
        "CFBundleName": "灵感晾台", "CFBundleDisplayName": "灵感晾台",
        "CFBundleIdentifier": "local.longhai.IdeaLine", "CFBundleExecutable": "IdeaLine",
        "CFBundleIconFile": "IdeaLine", "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleShortVersionString": version, "CFBundleVersion": build,
        "LSMinimumSystemVersion": "14.0", "LSUIElement": True, "NSHighResolutionCapable": True,
        "SUEnableAutomaticChecks": bool(feed), "SUAutomaticallyUpdate": False,
        "SUScheduledCheckInterval": 86400, "SUEnableSystemProfiling": False,
    }
    if feed:
        info.update(SUFeedURL=feed, SUPublicEDKey=key)
    return info


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(__file__).resolve().parent.parent / "release.json")
    parser.add_argument("--require-updates", action="store_true")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        info = bundle_info(json.loads(args.config.read_text()), args.require_updates)
        args.output.write_bytes(plistlib.dumps(info))
    except (ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
