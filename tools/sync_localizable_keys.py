#!/usr/bin/env python3
"""
Adds to facekey/Localizable.xcstrings every key the Swift compiler extracted
during the last build, without touching the keys and translations already there.

xcodebuild run with `-target` does not update string catalogs the way the Xcode
IDE does, but the compiler still writes one .stringsdata file per source file
into the build folder (SWIFT_EMIT_LOC_STRINGS = YES). This script reads those
files and merges their `Localizable` table into the catalog.

Usage:
    xcodebuild -project facekey.xcodeproj -target facekey -configuration Debug \
        CODE_SIGNING_ALLOWED=NO build
    python3 tools/sync_localizable_keys.py

Running it twice in a row changes nothing. Keys that are in the catalog but no
longer extracted are only reported, never deleted.
"""

from __future__ import annotations

import glob
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "facekey" / "Localizable.xcstrings"
# One architecture is enough: arm64 and x86_64 extract the same keys.
STRINGSDATA_GLOB = str(
    ROOT / "build" / "facekey.build" / "Debug" / "facekey.build" / "Objects-normal" / "arm64" / "*.stringsdata"
)


def extracted_keys() -> set[str]:
    keys: set[str] = set()
    for path in glob.glob(STRINGSDATA_GLOB):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for entry in data.get("tables", {}).get("Localizable", []):
            key = entry.get("key", "")
            if key:
                keys.add(key)
    return keys


def main() -> int:
    if not glob.glob(STRINGSDATA_GLOB):
        print("No .stringsdata files found: build the app first.", file=sys.stderr)
        return 1

    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)
    strings = catalog.setdefault("strings", {})

    extracted = extracted_keys()
    added = sorted(k for k in extracted if k not in strings)
    stale = sorted(k for k in strings if k not in extracted)
    for key in added:
        strings[key] = {}

    catalog["strings"] = dict(sorted(strings.items(), key=lambda kv: kv[0].lower()))
    if added:
        with open(CATALOG, "w", encoding="utf-8") as f:
            json.dump(catalog, f, indent=2, ensure_ascii=False, separators=(",", " : "))
            f.write("\n")

    print(f"{len(added)} keys added, {len(stale)} in the catalog but not extracted, {len(strings)} total.")
    for key in stale:
        print(f"  stale: {key!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
