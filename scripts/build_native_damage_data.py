#!/usr/bin/env python3
"""Build the data bundle used by the native Swift damage calculator.

The iOS app must not load the web calculator or execute its JavaScript.  This
script only converts/copies *data* from the checked-in website snapshot into a
folder reference that Swift can read through ``Bundle.main``:

* weapon JSON files and the enemy table;
* a compact searchable weapon index with Chinese names;
* the website's Chinese localization dictionary;
* locally cached weapon and Mod thumbnails when they are available.

It deliberately does not copy ``min.js``, HTML, CSS, or a WebKit shim.  Mod
effects remain in DamageKit's own SwiftPM resource bundle, exported from the
same upstream ``modsProps`` dataset by ``scripts/export_mods.js``.
"""

from __future__ import annotations

import json
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "server" / "site"
DEST = ROOT / "ios" / "DamageData"
ICON_SOURCE = ROOT / "assets" / "weapon-icons"
MOD_ICON_SOURCE = ROOT / "assets" / "mod-icons"
EXTRA_ICON_SOURCE = ROOT / "assets" / "extra-icons"
EXTRA_ZH_SOURCE = ROOT / "assets" / "extra-zh.json"
NODE = shutil.which("node") or "node"

CAT_ORDER = {
    "Primary": 0,
    "Secondary": 1,
    "Melee": 2,
    "Archgun": 3,
    "Exalted Weapon": 4,
}


def read_locale() -> dict[str, str]:
    """Evaluate the upstream ``localeLang`` object and serialize only data.

    ``zh.js`` is JavaScript, not JSON.  Node is used at build time because it
    is already required by the existing site-data tooling; the resulting iOS
    bundle is JSON and the app itself has no JavaScript runtime dependency.
    """

    source = SITE / "zh.js"
    if not source.exists():
        raise FileNotFoundError(source)
    program = source.read_text(encoding="utf-8") + "\nprocess.stdout.write(JSON.stringify(localeLang));"
    completed = subprocess.run(
        [NODE, "-"],
        input=program.encode("utf-8"),
        capture_output=True,
        timeout=60,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", "replace")[:600]
        raise RuntimeError(f"cannot parse {source.name}: {detail}")
    raw = json.loads(completed.stdout.decode("utf-8"))
    locale = {str(key): str(value) for key, value in raw.items()}
    if EXTRA_ZH_SOURCE.exists():
        extra = json.loads(EXTRA_ZH_SOURCE.read_text(encoding="utf-8"))
        for key, value in extra.items():
            k = str(key)
            v = str(value)
            if k not in locale or locale[k] == k:
                locale[k] = v
    return locale


def make_weapon_index(manifest: dict[str, str], locale: dict[str, str]) -> list[dict[str, object]]:
    out: list[dict[str, object]] = []
    for name, filename in manifest.items():
        path = SITE / "weapons" / filename
        try:
            weapon = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - report every bad source path
            raise RuntimeError(f"cannot read weapon {name} ({filename}): {exc}") from exc
        if not weapon.get("attacks"):
            continue
        out.append(
            {
                "n": name,
                "z": locale.get(name, name),
                "c": weapon.get("category") or "",
                "t": weapon.get("type") or "",
                "img": weapon.get("imageName") or "",
                "mr": weapon.get("masteryReq") or 0,
                "atk": [attack["name"] for attack in weapon["attacks"] if attack.get("name")],
                "inc": bool(weapon.get("incarnon")),
            }
        )
    out.sort(key=lambda item: (CAT_ORDER.get(str(item["c"]), 9), str(item["z"])))
    return out


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_generated_bundle(locale: dict[str, str], index: list[dict[str, object]]) -> None:
    """Fail the build if the iOS bundle ceased to be an exact data copy.

    Weapon records and the enemy table are intentionally copied without a
    schema translation.  Chinese labels are the one derived JSON file, so
    compare that dictionary semantically.  This is deliberately part of the
    generator rather than a best-effort CI report: a native build must not
    silently ship a stale calculation input bundle.
    """

    source_weapons = sorted(
        path.relative_to(SITE / "weapons")
        for path in (SITE / "weapons").rglob("*") if path.is_file()
    )
    bundle_weapons = sorted(
        path.relative_to(DEST / "weapons")
        for path in (DEST / "weapons").rglob("*") if path.is_file()
    )
    if source_weapons != bundle_weapons:
        raise RuntimeError("DamageData weapon file list differs from server/site")
    for relative in source_weapons:
        source = SITE / "weapons" / relative
        bundle = DEST / "weapons" / relative
        if sha256(source) != sha256(bundle):
            raise RuntimeError(f"DamageData weapon differs from source: {relative}")

    source_enemy = SITE / "data" / "json" / "enemies-min.json"
    bundle_enemy = DEST / "data" / "json" / "enemies-min.json"
    if sha256(source_enemy) != sha256(bundle_enemy):
        raise RuntimeError("DamageData enemy table differs from server/site")

    bundle_locale = json.loads((DEST / "zh-Hans.json").read_text(encoding="utf-8"))
    if bundle_locale != locale:
        raise RuntimeError("DamageData Chinese localization differs from server/site")

    bundle_index = json.loads((DEST / "weapons-list.json").read_text(encoding="utf-8"))
    if bundle_index != index:
        raise RuntimeError("DamageData weapon index differs from generated source index")


def main() -> int:
    required = [
        SITE / "weapons.json",
        SITE / "weapons",
        SITE / "data" / "json" / "enemies-min.json",
        SITE / "zh.js",
    ]
    absent = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    if absent:
        print("[x] native damage data source missing: " + ", ".join(absent), file=sys.stderr)
        return 1

    locale = read_locale()
    manifest = json.loads((SITE / "weapons.json").read_text(encoding="utf-8"))
    index = make_weapon_index(manifest, locale)

    # DEST is a generated, dedicated directory (ignored by Git).  Replacing it
    # cannot touch user inventory, app resources, or source data.
    if DEST.exists():
        shutil.rmtree(DEST)
    (DEST / "data" / "json").mkdir(parents=True)

    shutil.copytree(SITE / "weapons", DEST / "weapons")
    shutil.copy2(SITE / "data" / "json" / "enemies-min.json", DEST / "data" / "json" / "enemies-min.json")
    (DEST / "weapons-list.json").write_text(
        json.dumps(index, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    (DEST / "zh-Hans.json").write_text(
        json.dumps(locale, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    verify_generated_bundle(locale, index)

    icon_count = 0
    if ICON_SOURCE.exists():
        shutil.copytree(ICON_SOURCE, DEST / "icons")
        icon_count = sum(1 for _ in (DEST / "icons").glob("*.webp"))

    mod_icon_count = 0
    if MOD_ICON_SOURCE.exists():
        shutil.copytree(MOD_ICON_SOURCE, DEST / "mod-icons")
        mod_icon_count = sum(1 for _ in (DEST / "mod-icons").glob("*.webp"))

    extra_icon_count = 0
    if EXTRA_ICON_SOURCE.exists():
        shutil.copytree(EXTRA_ICON_SOURCE, DEST / "extra-icons")
        extra_icon_count = sum(1 for _ in (DEST / "extra-icons").glob("*.webp"))

    all_size = sum(path.stat().st_size for path in DEST.rglob("*") if path.is_file())
    print(
        f"[ok] {DEST.relative_to(ROOT)}  weapons={len(index)} "
        f"locale={len(locale)} weapon_icons={icon_count} mod_icons={mod_icon_count} "
        f"extra_icons={extra_icon_count} size={all_size / 1048576:.2f}MB"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
