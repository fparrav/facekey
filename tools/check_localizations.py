#!/usr/bin/env python3
"""
Checks that the string catalogs are complete in Spanish.

Fails (exit 1, naming the key) when a translatable entry:
  - has no `es` value,
  - has an `es` value whose state is not `translated`,
  - has an `es` value whose placeholders (%@, %lld, %1$@ ...) differ from the English source.

Entries marked `"shouldTranslate": false` (Face Lab, which is English on purpose) are skipped.

Usage:
    python3 tools/check_localizations.py

Spanish glossary (neutral Latin American Spanish, "tú", no voseo, no country slang).
Use one Spanish term per English term so the app reads the same everywhere:
    identity    = identidad
    session     = sesión
    liveness    = detección de vida
    enrollment  = registro (del rostro)
    capture     = captura
    notch       = notch
    lock screen = pantalla de bloqueo
System names follow macOS in Spanish: "Ajustes del Sistema", "Accesibilidad", "Cámara",
"Privacidad y seguridad".
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    ROOT / "facekey" / "Localizable.xcstrings",
    ROOT / "facekey" / "InfoPlist.xcstrings",
]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:l{0,2}[dux]|[@fsc])|%%")


def placeholders(text: str) -> list[str]:
    """Placeholder types in sorted order; positions (%1$@) do not matter, only the types."""
    found = []
    for match in PLACEHOLDER.finditer(text):
        token = match.group(0)
        if token == "%%":
            continue
        found.append(re.sub(r"^%\d+\$", "%", token))
    return sorted(found)


def string_units(node: object):
    """Every stringUnit under a localization, including plural and device variations."""
    if isinstance(node, dict):
        unit = node.get("stringUnit")
        if isinstance(unit, dict):
            yield unit
        for key, value in node.items():
            if key != "stringUnit":
                yield from string_units(value)
    elif isinstance(node, list):
        for item in node:
            yield from string_units(item)


def check_catalog(path: Path) -> list[str]:
    problems: list[str] = []
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("shouldTranslate") is False:
            continue
        label = f"{path.name}: {key!r}"
        localization = entry.get("localizations", {}).get("es")
        if not localization:
            problems.append(f"{label} has no Spanish translation")
            continue
        units = list(string_units(localization))
        if not units:
            problems.append(f"{label} has no Spanish value")
            continue
        english = (
            entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", key)
        )
        for unit in units:
            value = unit.get("value", "")
            if not value:
                problems.append(f"{label} has an empty Spanish value")
            elif unit.get("state") != "translated":
                problems.append(f"{label} is in state {unit.get('state')!r}, not 'translated'")
            elif placeholders(value) != placeholders(english):
                problems.append(
                    f"{label} placeholders differ: English {placeholders(english)}, Spanish {placeholders(value)}"
                )
    return problems


def main() -> int:
    problems: list[str] = []
    checked = 0
    for path in CATALOGS:
        if not path.exists():
            problems.append(f"{path} is missing")
            continue
        problems += check_catalog(path)
        checked += 1
    if problems:
        for problem in problems:
            print(problem)
        print(f"FAIL: {len(problems)} problem(s) in {checked} catalog(s).")
        return 1
    print(f"OK: {checked} catalogs complete in Spanish.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
