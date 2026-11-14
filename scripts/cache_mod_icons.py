#!/usr/bin/env python3
"""Download the Mod thumbnails referenced by DamageKit's checked-in data.

The iOS calculator must remain usable without a network connection.  The
website's Mod records point at image names (for example ``Serration.webp``),
but its picker obtains a real URL through ``/getImg.php``.  That endpoint
resolves to ``/data/mods/<name>``; the generated app bundle therefore carries
an audited local cache under ``assets/mod-icons``.

This script only writes inside its dedicated destination.  It verifies that
each response is an image before replacing a file, and it never silently
substitutes a placeholder for a failed asset.

Examples:
  python3 scripts/cache_mod_icons.py --limit 3
  python3 scripts/cache_mod_icons.py --strict
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import sys
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent
MODS = ROOT / "Packages" / "DamageKit" / "Sources" / "DamageKit" / "Resources" / "mods.json"
DEFAULT_DESTINATION = ROOT / "assets" / "mod-icons"
EXCEPTIONS = ROOT / "scripts" / "mod_icon_upstream_exceptions.json"
BASE_URL = "https://warframe-damage.com/data/mods/"


def requested_names() -> list[str]:
    records = json.loads(MODS.read_text(encoding="utf-8"))
    names = {str(record.get("img") or "").strip() for record in records}
    # Riven is constructed dynamically by the website rather than stored in
    # modsProps, but the native UI offers the same editor.
    names.add("riven.webp")
    return sorted(name for name in names if name and "/" not in name and "\\" not in name)


def known_unavailable() -> dict[str, dict[str, str]]:
    """Read the small, reviewed list of assets absent from the source site.

    This is deliberately an allow-list rather than a generic "ignore errors"
    switch: a new failed image still makes --strict fail, and an asset that
    later appears upstream is downloaded normally.
    """

    try:
        raw = json.loads(EXCEPTIONS.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid icon exception list {EXCEPTIONS}: {error}") from error
    entries = raw.get("unavailable", {})
    if not isinstance(entries, dict):
        raise RuntimeError(f"invalid icon exception list {EXCEPTIONS}: unavailable must be an object")
    return {
        str(name): {str(key): str(value) for key, value in details.items()}
        for name, details in entries.items()
        if isinstance(details, dict)
    }


def is_image(content_type: str, data: bytes) -> bool:
    declared_image = content_type.lower().split(";", 1)[0].strip().startswith("image/")
    webp = len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    png = data.startswith(b"\x89PNG\r\n\x1a\n")
    jpeg = data.startswith(b"\xff\xd8\xff")
    return declared_image and (webp or png or jpeg)


def fetch(name: str, timeout: float) -> bytes:
    url = BASE_URL + quote(name)
    request = Request(url, headers={"User-Agent": "WarframeWatch-native-icon-cache/1.0"})
    with urlopen(request, timeout=timeout) as response:  # noqa: S310 - fixed https origin above
        content_type = response.headers.get_content_type()
        payload = response.read()
    if not is_image(content_type, payload):
        raise ValueError(f"{name}: response is not a valid image ({content_type}, {len(payload)} bytes)")
    return payload


def atomic_write(destination: Path, data: bytes) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
    temporary.replace(destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=DEFAULT_DESTINATION,
                        help="only this directory may be written (default: assets/mod-icons)")
    parser.add_argument("--limit", type=int, default=0,
                        help="fetch at most N icons; useful to test connectivity")
    parser.add_argument("--refresh", action="store_true", help="redownload valid cached files")
    parser.add_argument("--strict", action="store_true", help="return failure if any requested icon is missing")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--workers", type=int, default=8,
                        help="parallel downloads (default: 8; set 1 for serial diagnostics)")
    arguments = parser.parse_args()

    destination = arguments.dest.resolve()
    expected_root = DEFAULT_DESTINATION.resolve()
    if destination != expected_root:
        print(f"[x] refusing to write outside dedicated Mod cache: {destination}", file=sys.stderr)
        return 2

    names = requested_names()
    unavailable = known_unavailable()
    if arguments.limit > 0:
        names = names[: arguments.limit]
    pending: list[tuple[int, str]] = []
    reused = 0
    for index, name in enumerate(names, start=1):
        target = destination / name
        if target.exists() and not arguments.refresh:
            data = target.read_bytes()
            if is_image("image/" + target.suffix.lstrip("."), data):
                reused += 1
                continue

        pending.append((index, name))

    def cache_one(item: tuple[int, str]) -> tuple[int, str, str | None]:
        index, name = item
        try:
            atomic_write(destination / name, fetch(name, arguments.timeout))
            return index, name, None
        except (HTTPError, URLError, TimeoutError, ValueError, OSError) as error:
            return index, name, str(error)

    downloaded = 0
    failed: list[str] = []
    expected_missing: list[str] = []
    workers = max(1, min(arguments.workers, 16))
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(cache_one, item) for item in pending]
        for future in as_completed(futures):
            index, name, error = future.result()
            if error is None:
                downloaded += 1
                print(f"[{index}/{len(names)}] cached {name}")
                continue
            if name in unavailable:
                expected_missing.append(name)
                print(f"[!] upstream image unavailable (reviewed): {name}: {unavailable[name].get('reason', error)}",
                      file=sys.stderr)
            else:
                failed.append(f"{name}: {error}")
                print(f"[x] {failed[-1]}", file=sys.stderr)

    print(
        f"[ok] requested={len(names)} downloaded={downloaded} reused={reused} "
        f"known_unavailable={len(expected_missing)} failed={len(failed)}"
    )
    if failed and arguments.strict:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
