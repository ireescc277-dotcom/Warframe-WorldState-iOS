#!/usr/bin/env python3
"""Verify the checked-in Mod thumbnail cache without contacting the network."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MODS = ROOT / "Packages" / "DamageKit" / "Sources" / "DamageKit" / "Resources" / "mods.json"
CACHE = ROOT / "assets" / "mod-icons"
EXCEPTIONS = ROOT / "scripts" / "mod_icon_upstream_exceptions.json"


def is_image(path: Path) -> bool:
    data = path.read_bytes()
    return (
        (len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP")
        or data.startswith(b"\x89PNG\r\n\x1a\n")
        or data.startswith(b"\xff\xd8\xff")
    )


def main() -> int:
    records = json.loads(MODS.read_text(encoding="utf-8"))
    expected = {str(row.get("img") or "").strip() for row in records}
    expected = {name for name in expected if name}
    expected.add("riven.webp")

    raw_exceptions = json.loads(EXCEPTIONS.read_text(encoding="utf-8"))
    unavailable = set(raw_exceptions.get("unavailable", {}))
    cached = {path.name for path in CACHE.iterdir() if path.is_file()}
    missing = sorted(expected - cached - unavailable)
    stale_exceptions = sorted(unavailable & cached)
    unexpected = sorted(cached - expected)
    malformed = sorted(path.name for path in CACHE.iterdir() if path.is_file() and not is_image(path))
    digest = hashlib.sha256(
        "\n".join(f"{path.name}:{hashlib.sha256(path.read_bytes()).hexdigest()}"
                  for path in sorted(CACHE.iterdir(), key=lambda item: item.name)
                  if path.is_file()).encode("utf-8")
    ).hexdigest()

    report = {
        "expected": len(expected),
        "cached": len(cached),
        "knownUnavailable": sorted(unavailable),
        "missing": missing,
        "staleExceptions": stale_exceptions,
        "unexpected": unexpected,
        "malformed": malformed,
        "cacheDigest": digest,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if missing or stale_exceptions or unexpected or malformed else 0


if __name__ == "__main__":
    raise SystemExit(main())
