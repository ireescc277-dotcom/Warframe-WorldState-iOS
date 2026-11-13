#!/usr/bin/env python3
"""Build assets/mod-cards-zh.json from local DE PublicExport JSONs and DamageKit mods.json."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "gamedata" / "raw"
MODS_JSON = ROOT / "Packages" / "DamageKit" / "Sources" / "DamageKit" / "Resources" / "mods.json"
MOD_ART_INDEX_PATH = ROOT / "assets" / "mod-art-index.json"
OUT_PATH = ROOT / "assets" / "mod-cards-zh.json"

POLARITY_MAP = {
    "AP_ATTACK": "Madurai",
    "AP_DEFENSE": "Vazarin",
    "AP_TACTIC": "Naramon",
    "AP_POWER": "Zenurik",
    "AP_WARD": "Unairu",
    "AP_PRECEPT": "Penjaga",
    "AP_UMBRA": "Umbra",
    "AP_ANY": "Aura",
}

TYPE_COMPAT_ZH = {
    "PRIMARY": "主要武器",
    "SECONDARY": "次要武器",
    "MELEE": "近战",
    "WARFRAME": "战甲",
    "COMPANION": "同伴",
    "ARCHWING": "Archwing",
    "ARCHGUN": "Archwing 重武器",
    "ARCHMELEE": "Archwing 近战",
    "STANCE": "架势",
    "AURA": "光环",
    "PARAZON": "灭骸之刃",
}

TAG_RE = re.compile(r"<[^>]+>")


def clean_stat_line(raw: str) -> str:
    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    text = TAG_RE.sub("", text)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return "\n".join(lines)


def dedupe_stats(level_stats: list[dict]) -> list[str]:
    ranks: list[str] = []
    for lvl in level_stats:
        raw_lines = lvl.get("stats") or []
        seen: list[str] = []
        for entry in raw_lines:
            cleaned = clean_stat_line(str(entry))
            for sub in cleaned.splitlines():
                sub = sub.strip()
                if sub and sub not in seen:
                    seen.append(sub)
        ranks.append("\n".join(seen))
    return ranks


def upgrade_priority(entry: dict) -> tuple[int, int, int]:
    uname = entry.get("uniqueName", "")
    is_pvp = 1 if "/PvPMods/" in uname or "PvP" in uname else 0
    is_beginner = 1 if ("Beginner" in uname or "Flawed" in entry.get("name", "")) else 0
    is_secret = 1 if entry.get("codexSecret") else 0
    return (is_pvp, is_beginner, is_secret)


def determine_frame_tier(en_name: str, rarity: str, is_arcane: bool) -> str:
    if is_arcane:
        return "Arcane"
    if en_name.startswith("Galvanized "):
        return "Galvanized"
    if en_name.startswith("Amalgam "):
        return "Amalgam"
    if "Riven Mod" in en_name:
        return "Omega"
    upper_rarity = rarity.upper()
    if upper_rarity == "LEGENDARY":
        return "Legendary"
    if upper_rarity == "RARE":
        return "Gold"
    if upper_rarity == "UNCOMMON":
        return "Silver"
    return "Bronze"


def build_catalog() -> dict[str, dict]:
    up_en = json.loads((RAW_DIR / "ExportUpgrades_en.json").read_text(encoding="utf-8"))["ExportUpgrades"]
    up_zh = json.loads((RAW_DIR / "ExportUpgrades_zh.json").read_text(encoding="utf-8"))["ExportUpgrades"]
    ra_en = json.loads((RAW_DIR / "ExportRelicArcane_en.json").read_text(encoding="utf-8"))["ExportRelicArcane"]
    ra_zh = json.loads((RAW_DIR / "ExportRelicArcane_zh.json").read_text(encoding="utf-8"))["ExportRelicArcane"]

    art_index: dict[str, dict] = {}
    if MOD_ART_INDEX_PATH.exists():
        art_index = json.loads(MOD_ART_INDEX_PATH.read_text(encoding="utf-8"))
    lower_art_index = {k.lower(): v for k, v in art_index.items()}

    zh_by_unique = {item["uniqueName"]: item for item in up_zh if item.get("uniqueName")}
    ra_zh_by_unique = {item["uniqueName"]: item for item in ra_zh if item.get("uniqueName")}

    cards: dict[str, tuple[tuple[int, int, int], dict]] = {}

    for item in up_en:
        name = (item.get("name") or "").strip()
        uname = item.get("uniqueName") or ""
        if not name or not uname:
            continue
        zh_item = zh_by_unique.get(uname, {})
        zh_name = (zh_item.get("name") or "").strip() or name
        level_stats = zh_item.get("levelStats") or item.get("levelStats") or []
        ranks = dedupe_stats(level_stats)
        fusion_limit = item.get("fusionLimit")
        if fusion_limit is None:
            fusion_limit = max(0, len(ranks) - 1)
        compat = (zh_item.get("compatName") or item.get("compatName") or "").strip()
        if not compat:
            compat = TYPE_COMPAT_ZH.get((item.get("type") or "").upper(), "")
        rarity = (item.get("rarity") or "COMMON").upper()
        art_meta = art_index.get(name) or lower_art_index.get(name.lower()) or {}
        card = {
            "name": zh_name,
            "polarity": POLARITY_MAP.get(item.get("polarity") or "", ""),
            "rarity": rarity,
            "baseDrain": int(item.get("baseDrain") or 0),
            "maxRank": int(fusion_limit),
            "compat": compat,
            "isArcane": False,
            "art": art_meta.get("art") or "",
            "frameTier": determine_frame_tier(name, rarity, False),
            "modSet": art_meta.get("modSet") or "",
            "ranks": ranks,
        }
        prio = upgrade_priority(item)
        if name not in cards or prio < cards[name][0]:
            cards[name] = (prio, card)

    for item in ra_en:
        name = (item.get("name") or "").strip()
        uname = item.get("uniqueName") or ""
        if not name or not uname or not item.get("levelStats"):
            continue
        zh_item = ra_zh_by_unique.get(uname, {})
        zh_name = (zh_item.get("name") or "").strip() or name
        level_stats = zh_item.get("levelStats") or item.get("levelStats") or []
        ranks = dedupe_stats(level_stats)
        rarity = (item.get("rarity") or "RARE").upper()
        art_meta = art_index.get(name) or lower_art_index.get(name.lower()) or {}
        card = {
            "name": zh_name,
            "polarity": "",
            "rarity": rarity,
            "baseDrain": 0,
            "maxRank": max(0, len(ranks) - 1),
            "compat": "赋能",
            "isArcane": True,
            "art": art_meta.get("art") or "",
            "frameTier": determine_frame_tier(name, rarity, True),
            "modSet": "",
            "ranks": ranks,
        }
        prio = (0, 0, 1 if item.get("codexSecret") else 0)
        if name not in cards or prio < cards[name][0]:
            cards[name] = (prio, card)

    result = {k: v[1] for k, v in sorted(cards.items())}

    # Alias legacy names used in DamageKit / WarframeStat exports
    lower_lookup = {k.lower(): k for k in result}
    for alias, canonical in [
        ("Bane Of The Murmur", "Bane of The Murmur"),
        ("Bane of Corrupted", "Bane of Orokin"),
        ("Cleanse Corrupted", "Cleanse Orokin"),
        ("Expel Corrupted", "Expel Orokin"),
        ("Smite Corrupted", "Smite Orokin"),
        ("Primed Bane of Corrupted", "Primed Bane of Orokin"),
        ("Primed Cleanse Corrupted", "Primed Cleanse Orokin"),
        ("Primed Expel Corrupted", "Primed Expel Orokin"),
        ("Primed Smite Corrupted", "Primed Smite Orokin"),
    ]:
        src = result.get(canonical) or result.get(lower_lookup.get(canonical.lower(), ""))
        if src and alias not in result:
            result[alias] = src

    return result


def main() -> int:
    catalog = build_catalog()
    mods_json = json.loads(MODS_JSON.read_text(encoding="utf-8"))
    mods_keys = {m.get("name") for m in mods_json if isinstance(m, dict) and m.get("name")}
    missing_from_mods = sorted(k for k in mods_keys if k not in catalog)
    OUT_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"[ok] {OUT_PATH.relative_to(ROOT)} entries={len(catalog)} size={OUT_PATH.stat().st_size / 1024:.1f}KB")
    print(f"mods.json keys covered: {len(mods_keys) - len(missing_from_mods)}/{len(mods_keys)}; missing={missing_from_mods}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
