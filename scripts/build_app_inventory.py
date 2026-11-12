#!/usr/bin/env python3
"""把背包快照、市场价、Ducats 价和当期 Aya 商店合并成 App 用的资源文件。

输入
    data/inventory/view.json          build_inventory_view.py 产出
    data/market/items.json            wf_market.py items 产出（gameRef → slug）
    data/market/prices.json           wf_market.py sync 产出
    cachedData/json/Components.json   部件的 primeSellingPrice（Ducats）
    api.warframestat.us/pc            vaultTrader.inventory 里 credits=1 的就是当期 Aya 遗物

输出
    WarframeWatch/Resources/InventoryData.json

体积控制在 150 KB 以内：只保留 App 会显示的字段，键名压到一个字母。
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW = os.path.join(ROOT, "data", "inventory", "view.json")
SNAPSHOT = os.path.join(ROOT, "data", "inventory", "latest.json.gz")
SNAPSHOT_META = os.path.join(ROOT, "data", "inventory", "latest.meta.json")
GAMEDATA = os.path.join(ROOT, "data", "gamedata", "gamedata.json")
RIVEN_TAGS = os.path.join(ROOT, "data", "gamedata", "ref", "riven", "riven_tags.json")
MARKET_ITEMS = os.path.join(ROOT, "data", "market", "items.json")
MARKET_PRICES = os.path.join(ROOT, "data", "market", "prices.json")
ICONS = os.path.join(ROOT, "data", "market", "icons.json")
OUT = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.json")
CACHE = os.path.join(ROOT, "data", "inventory", "aya_cache.json")

ALECA = os.path.expandvars(r"%LOCALAPPDATA%\AlecaFrame\cachedData\json")
ALECA_WARFRAMES = os.path.join(ALECA, "Warframes.json")
ALECA_MODS = os.path.join(ALECA, "Mods.json")
ALECA_ARCANES = os.path.join(ALECA, "Arcanes.json")
ALECA_LANG = os.path.join(ALECA, "lang.json")
WS_URL = "https://api.warframestat.us/pc?language=zh"

# 精炼档的短键，顺序固定：完整 / 优良 / 无瑕 / 光辉
REFINE = [("Intact", "I"), ("Exceptional", "E"), ("Flawless", "F"), ("Radiant", "R")]
REFINE_ZH = {"Intact": "完整", "Exceptional": "优良", "Flawless": "无瑕", "Radiant": "光辉"}
ERA_ZH = {"Lith": "古纪", "Meso": "前纪", "Neo": "中纪", "Axi": "后纪", "Requiem": "安魂"}

# These category names match the calculator catalogue.  They deliberately do
# not try to pretend that a sentinel gun or an Arch-melee weapon is a normal
# primary: the weapon page must still show every owned instance, while the
# native calculator can explicitly say which types it currently understands.
OWNED_WEAPON_CATEGORIES = {
    "LongGuns": "Primary",
    "Pistols": "Secondary",
    "Melee": "Melee",
    "SentinelWeapons": "Companion",
    "SpaceGuns": "Archgun",
    "SpaceMelee": "Archmelee",
    # These are weapons in the AlecaFrame account snapshot too.  They may not
    # all be calculable yet, but hiding them makes the weapon page disagree
    # with the source inventory.
    "OperatorAmps": "Operator",
}

# These are equipment bodies rather than weapons.  They need their own model
# because a Sentinel/Pet/Archwing has A/B/C configurations but is not a
# primary/secondary weapon with a DamageKit definition.
OWNED_COMPANION_CATEGORIES = ("Sentinels", "KubrowPets", "MoaPets")
OWNED_ARCHWING_CATEGORIES = ("SpaceSuits",)

# `EquippedGear` contains account-level gear-wheel entries.  Only a stack
# source can provide a quantity; a gear body elsewhere in the snapshot must
# not be invented as one consumable charge.
GEAR_STACK_CATEGORIES = (
    "Consumables", "MiscItems", "Resources", "SpecialItems", "FlavourItems",
    "Recipes", "ShipDecorations", "WeaponSkins",
)


def is_companion_special_weapon(item: dict) -> bool:
    """Pet weapons live in `SpecialItems`, not in `SentinelWeapons`.

    A Sentinel/Pet preset can therefore correctly point at a Vulpaphyla or
    Kavat weapon instance which is absent from the normal SentinelWeapons
    list.  Exalted weapons in the same `SpecialItems` source are deliberately
    excluded: they are not an account-equipped companion weapon.
    """
    item_type = item.get("ItemType") if isinstance(item, dict) else None
    return isinstance(item_type, str) and "/Pets/" in item_type and item_type.endswith("Weapon")

# DamageKit has the same compatibility aliases in InventoryAdapter.swift.
# Keeping this small table here makes a generated mobile snapshot preserve
# installed weapon Arcanes without leaking inventory instance IDs.
UPGRADE_ALIASES = {
    "/Lotus/Upgrades/CosmeticEnhancers/Offensive/PrimaryDamageOnKill":
        ("Primary Merciless", 5),
    "/Lotus/Upgrades/CosmeticEnhancers/Offensive/SecondaryDamageOnKill":
        ("Secondary Merciless", 5),
    "/Lotus/Upgrades/CosmeticEnhancers/Offensive/MeleeDamageOnKill":
        ("Melee Merciless", 5),
    "/Lotus/Upgrades/CosmeticEnhancers/Offensive/SecondaryDamageOnHeatProc":
        ("Cascadia Flare", 5),
}

RIVEN_MAXIMUM = 1_073_741_823.0
RIVEN_BUFF_ATTENUATION = [0, 1, 0.66000003, 0.5, 0.40000001, 0.34999999]
RIVEN_CURSE_ATTENUATION = [0, 1, 0.33000001, 0.5, 1.25, 1.5]


# These names are the stable, public-facing effects that DamageKit already
# understands as Archon-shard inputs.  The account snapshot tells us which
# crystal is installed; it does *not* justify asking the player to select a
# second, unrelated shard in the calculator.
ARCHON_SHARD_EFFECTS = {
    "ArchonCrystalUpgradeWarframeAbilityStrength": {
        "name": "赤红执政官石 · 技能强度 +10%",
        "abilityStrength": 0.10,
    },
    "ArchonCrystalUpgradeWarframeAbilityStrengthMythic": {
        "name": "赤红执政官石（满铸）· 技能强度 +15%",
        "abilityStrength": 0.15,
    },
    "ArchonCrystalUpgradePrimaryStatusChance": {
        "name": "赤红执政官石 · 主武器状态几率 +25%",
        "damageKitName": "+25% Status Chance",
    },
    "ArchonCrystalUpgradePrimaryStatusChanceMythic": {
        "name": "赤红执政官石（满铸）· 主武器状态几率 +37.5%",
        "damageKitName": "+37.5% Status Chance",
    },
    "ArchonCrystalUpgradeSecondaryCritChance": {
        "name": "赤红执政官石 · 副武器暴击率 +25%",
        "damageKitName": "+25% Critical Chance",
    },
    "ArchonCrystalUpgradeSecondaryCritChanceMythic": {
        "name": "赤红执政官石（满铸）· 副武器暴击率 +37.5%",
        "damageKitName": "+37.5% Critical Chance",
    },
    "ArchonCrystalUpgradeWarframeCorrosiveStack": {
        "name": "绿宝石执政官石 · 腐蚀层数上限 +2",
        "damageKitName": "Incr. max stacks of Corrosion +2",
    },
    "ArchonCrystalUpgradeWarframeCorrosiveStackMythic": {
        "name": "绿宝石执政官石（满铸）· 腐蚀层数上限 +3",
        "damageKitName": "Incr. max stacks of Corrosion +3",
    },
    "ArchonCrystalUpgradeWarframeToxinDamage": {
        "name": "绿宝石执政官石 · 毒素状态伤害 +30%",
        "damageKitName": "Toxin Status +30% more damage",
    },
    "ArchonCrystalUpgradeWarframeToxinDamageMythic": {
        "name": "绿宝石执政官石（满铸）· 毒素状态伤害 +45%",
        "damageKitName": "Toxin Status +45% more damage",
    },
}


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def file_iso(path: str) -> str | None:
    """Filesystem observation time, used only in local diagnostics.

    It is intentionally not put into the App payload.  A cache file can be
    rewritten with identical account data, and treating that write time as a
    new account version is exactly how a newer-looking timestamp can become
    detached from its actual content.
    """
    try:
        return datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
    except OSError:
        return None


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_json_write(path: str, payload: dict) -> None:
    """Write a complete JSON document or leave the previous one intact."""
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def as_number(value) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def object_id(value) -> str | None:
    if isinstance(value, dict):
        raw = value.get("$oid")
        return raw if isinstance(raw, str) and raw else None
    return value if isinstance(value, str) and value else None


def fingerprint(value) -> dict | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = json.loads(value)
    except (TypeError, ValueError):
        return None
    return parsed if isinstance(parsed, dict) else None


def short_type_name(value: str) -> str:
    """A safe diagnostic label; never put a private instance ID in the app."""
    return value.rstrip("/").rsplit("/", 1)[-1] or "未知条目"


def source_sync_iso(inv: dict) -> str | None:
    raw = inv.get("LastInventorySync")
    if isinstance(raw, dict):
        oid = raw.get("$oid")
        if isinstance(oid, str) and len(oid) >= 8:
            try:
                return datetime.fromtimestamp(int(oid[:8], 16), timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
            except ValueError:
                return None
    return raw if isinstance(raw, str) else None


def alias_ref(ref: str) -> str | None:
    for suffix, other in (("Component", "Blueprint"), ("Blueprint", "Component")):
        if ref.endswith(suffix):
            return ref[: -len(suffix)] + other
    return None


def relic_ref_base(ref: str) -> str:
    """遗物 uniqueName 带 Bronze/Silver/Gold/Platinum 后缀，market 的 gameRef 不带。"""
    for suffix in ("Bronze", "Silver", "Gold", "Platinum"):
        if ref.endswith(suffix):
            return ref[: -len(suffix)]
    return ref


def load_json(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_inventory_snapshot() -> tuple[dict, bytes, dict]:
    """Return the decrypted snapshot plus stable, non-secret source metadata.

    `latest.json.gz` is written by `wf_inventory.py` after it has read
    AlecaFrame's cache.  The SHA-256 is over its plaintext JSON, so gzip header
    time and filesystem mtime cannot create a fake new account version.
    """
    with gzip.open(SNAPSHOT, "rb") as fh:
        raw = fh.read()
    inv = json.loads(raw)
    meta = load_json(SNAPSHOT_META) if os.path.exists(SNAPSHOT_META) else {}
    return inv, raw, {
        "accountHash": sha256(raw),
        "accountSync": source_sync_iso(inv),
        # Kept for local stage receipts.  The value never participates in the
        # App payload version comparison.
        "observedAt": file_iso(SNAPSHOT),
        "capturedAt": meta.get("captured_at"),
    }


def riven_value(raw: dict, *, curse: bool, disposition: float,
                tags: dict[str, dict], buff_count: int, curse_count: int,
                rank: int) -> float | None:
    tag = raw.get("Tag")
    row = tags.get(tag) if isinstance(tag, str) else None
    base = as_number(row.get("value")) if isinstance(row, dict) else None
    stored = as_number(raw.get("Value"))
    if base is None or stored is None:
        return None
    result = base * 1.5 * disposition * 10 * (-1 if curse else 1)
    if curse:
        result *= RIVEN_CURSE_ATTENUATION[min(buff_count, 5)]
        result *= RIVEN_BUFF_ATTENUATION[min(curse_count, 5)]
    else:
        result *= pow(1.25, curse_count)
        result *= RIVEN_BUFF_ATTENUATION[min(buff_count, 5)]
    fraction = min(max(stored / RIVEN_MAXIMUM, 0), 1)
    result *= 0.9 + 0.2 * fraction
    result *= rank + 1
    # InventoryAdapter rounds to four decimal places before constructing the
    # DamageKit Riven.  Do the same at the serialization boundary.
    return round(result, 4)


def riven_name(buffs: list[dict], tags: dict[str, dict]) -> str:
    ordered = sorted(buffs, key=lambda row: as_number(row.get("Value")) or 0, reverse=True)
    pieces: list[str] = []
    for index, buff in enumerate(ordered):
        tag = buff.get("Tag")
        row = tags.get(tag) if isinstance(tag, str) else None
        if not isinstance(row, dict):
            continue
        if index == len(ordered) - 1:
            suffix = row.get("suffix")
            if isinstance(suffix, str):
                pieces.append(suffix)
        elif index == 0:
            prefix = row.get("prefix")
            if isinstance(prefix, str) and prefix:
                pieces.append(prefix[:1].upper() + prefix[1:])
        else:
            prefix = row.get("prefix")
            if isinstance(prefix, str) and prefix:
                pieces.append("-" + prefix)
    return "".join(pieces) or "Riven"


RIVEN_UNRESOLVED_LABELS = {
    "WeaponAmmoEfficiency": "弹药效率",
    "WeaponAmmoMaxMod": "最大弹药",
    "WeaponClipMaxMod": "弹匣容量",
    "WeaponCorrosiveDamageMod": "腐蚀伤害",
    "WeaponGasDamageMod": "毒气伤害",
    "WeaponMeleeComboBonusOnHitMod": "每次命中连击数",
    "WeaponMeleeComboEfficiencyMod": "连击效率",
    "WeaponMeleeComboInitialBonusMod": "初始连击",
    "WeaponMeleeFinisherDamageMod": "处决伤害",
    "WeaponMeleeRangeIncMod": "近战范围",
    "WeaponProjectileSpeedMod": "投射物速度",
    "WeaponPunctureDepthMod": "穿透距离",
    "WeaponRecoilReductionMod": "后坐力",
    "WeaponZoomFovMod": "变焦",
    "ComboDurationMod": "连击持续时间",
    "SlideAttackCritChanceMod": "滑行攻击暴击率",
}

def riven_unresolved_label(tag: str) -> str:
    """Readable name for a raw Riven tag that has no DamageKit rule yet."""
    return RIVEN_UNRESOLVED_LABELS.get(tag, tag)


def decode_riven(upgrade: dict, weapon_data: dict, riven_tags: dict) -> tuple[dict | None, str | None]:
    """Normalize a Riven exactly as DamageKit's InventoryAdapter does.

    The app receives only the resolved numerical effects.  It never receives
    the upgrade instance ID, account ID, or the encrypted Aleca cache.
    """
    fp = fingerprint(upgrade.get("UpgradeFingerprint"))
    item_type = upgrade.get("ItemType")
    if not fp or not isinstance(item_type, str):
        return None, "紫卡缺少可解析的词条数据"
    riven_type = item_type.rsplit("/", 1)[-1]
    rows = riven_tags.get(riven_type)
    if not isinstance(rows, list) or not rows:
        return None, f"紫卡类型未映射：{short_type_name(item_type)}"
    tags = {
        row["tag"]: row for row in rows
        if isinstance(row, dict) and isinstance(row.get("tag"), str)
    }
    buffs = [x for x in (fp.get("buffs") or []) if isinstance(x, dict)]
    curses = [x for x in (fp.get("curses") or []) if isinstance(x, dict)]
    rank = int(as_number(fp.get("lvl")) or 0)
    disposition = as_number(weapon_data.get("om")) or 1.2

    scalars: dict[str, float] = {}
    elements: dict[str, float] = {}
    physical: dict[str, float] = {}
    factions: dict[str, float] = {}
    unresolved: list[dict[str, str]] = []

    scalar_tags = {
        "WeaponProcTimeMod": "statusDuration",
        "WeaponCritDamageMod": "critDamage",
        "WeaponCritChanceMod": "critChance",
        "WeaponDamageAmountMod": "damage",
        "WeaponMeleeDamageMod": "damage",
        "WeaponFireIterationsMod": "multishot",
        "WeaponStunChanceMod": "statusChance",
        "WeaponFireRateMod": "fireRate",
        "WeaponReloadSpeedMod": "reloadSpeed",
    }
    element_tags = {
        "WeaponFireDamageMod": "heat", "WeaponHeatDamageMod": "heat",
        "WeaponFreezeDamageMod": "cold", "WeaponColdDamageMod": "cold",
        "WeaponElectricityDamageMod": "electricity",
        "WeaponToxinDamageMod": "toxin", "WeaponPoisonDamageMod": "toxin",
    }
    physical_tags = {
        "WeaponImpactDamageMod": "impact", "WeaponSlashDamageMod": "slash",
        "WeaponArmorPiercingDamageMod": "puncture", "WeaponPunctureDamageMod": "puncture",
    }
    faction_tags = {
        "WeaponFactionDamageGrineer": "Grineer",
        "WeaponMeleeFactionDamageGrineer": "Grineer",
        "WeaponFactionDamageCorpus": "Corpus",
        "WeaponMeleeFactionDamageCorpus": "Corpus",
        "WeaponFactionDamageInfested": "Infested",
        "WeaponMeleeFactionDamageInfested": "Infested",
        "WeaponFactionDamageCorrupted": "Orokin",
    }

    def add(raw: dict, curse: bool) -> None:
        tag = raw.get("Tag")
        if not isinstance(tag, str):
            return
        supported = tag in scalar_tags or tag in element_tags or tag in physical_tags or tag in faction_tags
        if not supported:
            unresolved.append({"tag": tag, "label": riven_unresolved_label(tag)})
            return
        value = riven_value(raw, curse=curse, disposition=disposition, tags=tags,
                            buff_count=len(buffs), curse_count=len(curses), rank=rank)
        if value is None:
            unresolved.append({"tag": tag, "label": riven_unresolved_label(tag)})
            return
        if tag in scalar_tags:
            key = scalar_tags[tag]
            scalars[key] = scalars.get(key, 0) + value
        elif tag in element_tags:
            key = element_tags[tag]
            elements[key] = elements.get(key, 0) + value
        elif tag in physical_tags:
            key = physical_tags[tag]
            physical[key] = physical.get(key, 0) + value
        elif tag in faction_tags:
            key = faction_tags[tag]
            factions[key] = factions.get(key, 0) + value

    for buff in buffs:
        add(buff, False)
    for curse in curses:
        add(curse, True)

    result: dict = {"name": riven_name(buffs, tags)}
    result.update(scalars)
    if factions:
        result["factionBonuses"] = factions
    if elements:
        result["elements"] = elements
    if physical:
        result["physical"] = physical
    if unresolved:
        # Preserve every raw tag that was not placed into a DamageKit formula.
        # A duplicate tag is still one card term for this purpose; it is not
        # silently turned into a different supported stat.
        result["unresolved"] = list({row["tag"]: row for row in unresolved}.values())
    return result, None


def progenitor_elements(weapon: dict) -> dict[str, float]:
    fp = fingerprint(weapon.get("UpgradeFingerprint"))
    if not fp:
        return {}
    names = {
        "InnateFireDamage": "heat", "InnateHeatDamage": "heat",
        "InnateFreezeDamage": "cold", "InnateColdDamage": "cold",
        "InnateElectricityDamage": "electricity",
        "InnateToxinDamage": "toxin", "InnatePoisonDamage": "toxin",
        "InnateMagDamage": "magnetic",
    }
    result: dict[str, float] = {}
    for buff in fp.get("buffs") or []:
        if not isinstance(buff, dict):
            continue
        tag = buff.get("Tag")
        raw_value = as_number(buff.get("Value"))
        element = names.get(tag) if isinstance(tag, str) else None
        if element is None or raw_value is None:
            continue
        result[element] = result.get(element, 0) + 0.25 + 0.35 * min(
            max(raw_value / RIVEN_MAXIMUM, 0), 1
        )
    return result


def calculator_slot(raw_slot: int, category: str) -> int:
    """DE stores gun Arcanes at raw index 9; DamageKit reserves index 9 for stance."""
    return 10 if category != "Melee" and raw_slot == 9 else raw_slot


def config_label(index: int) -> str:
    return chr(ord("A") + index) if 0 <= index < 26 else f"配置 {index + 1}"


def incarnon_choices(weapon: dict) -> tuple[list[int], str | None]:
    """Decode DE's compact per-tier SkillTree selection string.

    The game's inventory stores one digit per unlocked evolution tier.  The
    calculator has its own tier IDs, so the app maps this positional list onto
    the selected weapon's sorted incarnon tiers only after it loads that weapon
    definition.
    """
    raw = weapon.get("SkillTree")
    if raw in (None, ""):
        return [], None
    if not isinstance(raw, str) or not raw.isdigit():
        return [], "灵化进化选择格式无法识别，未自动带入"
    return [int(char) for char in raw], None


def build_owned_weapons(inv: dict) -> list[dict]:
    """Convert the account-only weapon instances into an app-safe view.

    This keeps the instance/config boundary that the old generic weapon list
    lost: two copies of one weapon remain separate rows and each A/B/C config
    retains its original slot order.  Raw ItemIds stay local; only a one-way
    row id reaches the mobile app.
    """
    game_data = load_json(GAMEDATA)
    game_weapons = game_data.get("weapons") if isinstance(game_data, dict) else {}
    game_mods = game_data.get("mods") if isinstance(game_data, dict) else {}
    game_weapons = game_weapons if isinstance(game_weapons, dict) else {}
    game_mods = game_mods if isinstance(game_mods, dict) else {}
    riven_tags = load_json(RIVEN_TAGS) if os.path.exists(RIVEN_TAGS) else {}

    upgrades: dict[str, dict] = {}
    upgrades_by_type: dict[str, list[dict]] = {}
    for raw in inv.get("Upgrades") or []:
        if not isinstance(raw, dict):
            continue
        item_id = object_id(raw.get("ItemId"))
        if item_id:
            upgrades[item_id] = raw
        item_type = raw.get("ItemType")
        if isinstance(item_type, str) and item_type:
            upgrades_by_type.setdefault(item_type, []).append(raw)

    result: list[dict] = []
    for inventory_category, calculator_category in OWNED_WEAPON_CATEGORIES.items():
        for ordinal, weapon in enumerate(inv.get(inventory_category) or []):
            if not isinstance(weapon, dict):
                continue
            item_type = weapon.get("ItemType")
            if not isinstance(item_type, str) or not item_type:
                continue
            weapon_data = game_weapons.get(item_type)
            weapon_data = weapon_data if isinstance(weapon_data, dict) else {}
            calc_name = weapon_data.get("n") if isinstance(weapon_data.get("n"), str) else None
            display_name = weapon_data.get("z") if isinstance(weapon_data.get("z"), str) else None
            if not display_name:
                raw_name = weapon.get("ItemName")
                display_name = raw_name if isinstance(raw_name, str) and raw_name else short_type_name(item_type)
            raw_instance_id = object_id(weapon.get("ItemId")) or f"{inventory_category}:{ordinal}:{item_type}"
            opaque_id = sha256(raw_instance_id.encode("utf-8"))[:20]
            incarnon, incarnon_issue = incarnon_choices(weapon)
            configs: list[dict] = []
            raw_configs = weapon.get("Configs") if isinstance(weapon.get("Configs"), list) else []
            if not raw_configs:
                raw_configs = [{}]

            for config_index, raw_config in enumerate(raw_configs):
                config = raw_config if isinstance(raw_config, dict) else {}
                slots: list[str | None] = [None] * 11
                issues: list[str] = []
                if incarnon_issue:
                    issues.append(incarnon_issue)
                riven: dict | None = None
                riven_slot: int | None = None
                raw_slots = config.get("Upgrades") if isinstance(config.get("Upgrades"), list) else []
                for raw_slot, upgrade_id in enumerate(raw_slots):
                    if not isinstance(upgrade_id, str) or not upgrade_id:
                        continue
                    slot = calculator_slot(raw_slot, calculator_category)
                    if not (0 <= slot < len(slots)):
                        issues.append(f"第 {raw_slot + 1} 槽超出当前计算器的槽位范围")
                        continue

                    # A literal type path in Configs records *which* Mod is
                    # equipped, but not the individual card id.  When every
                    # owned copy of that same type has one identical rank we
                    # can still recover the rank exactly; otherwise the
                    # source is ambiguous and must not be promoted to max.
                    direct_type_reference = upgrade_id.startswith("/")
                    direct_rank_issue: str | None = None
                    if direct_type_reference:
                        upgrade = {"ItemType": upgrade_id}
                        candidate_ranks = {
                            int(raw_rank)
                            for candidate in upgrades_by_type.get(upgrade_id, [])
                            for raw_rank in [as_number((fingerprint(candidate.get("UpgradeFingerprint")) or {}).get("lvl"))]
                            if raw_rank is not None
                        }
                        if len(candidate_ranks) == 1:
                            rank = next(iter(candidate_ranks))
                        elif not candidate_ranks:
                            rank = None
                            direct_rank_issue = (
                                "配置只记录了 Mod 类型，背包中没有可确定等级的同名 Mod；当前未带入"
                            )
                        else:
                            rank = None
                            ranks = "/".join(str(value) for value in sorted(candidate_ranks))
                            direct_rank_issue = (
                                f"配置只记录了 Mod 类型，而背包中同名 Mod 的等级有 {ranks}；"
                                "无法判断装备的是哪一张，当前未带入"
                            )
                    else:
                        upgrade = upgrades.get(upgrade_id)
                        rank = None
                    if not isinstance(upgrade, dict):
                        issues.append("此槽引用的已装 Mod 在背包快照中找不到，因此没有带入计算")
                        continue
                    upgrade_type = upgrade.get("ItemType")
                    if not isinstance(upgrade_type, str) or not upgrade_type:
                        issues.append("有一个已装升级没有类型信息")
                        continue

                    if "Randomized" in upgrade_type:
                        parsed, error = decode_riven(upgrade, weapon_data, riven_tags)
                        if error:
                            issues.append(error)
                        elif riven is not None:
                            issues.append("同一配置含有多个紫卡，当前计算器只能保留一个")
                        else:
                            riven, riven_slot = parsed, slot
                            unresolved = parsed.get("unresolved") if isinstance(parsed, dict) else None
                            if isinstance(unresolved, list) and unresolved:
                                issues.append(
                                    f"紫卡有 {len(unresolved)} 条词条尚无对应的伤害规则；"
                                    "已在紫卡区域逐条标出，未写入计算"
                                )
                        continue

                    alias = UPGRADE_ALIASES.get(upgrade_type)
                    if alias:
                        name, maximum = alias
                    else:
                        mod_data = game_mods.get(upgrade_type)
                        if not isinstance(mod_data, dict) or not isinstance(mod_data.get("n"), str):
                            issues.append(f"未映射的武器升级：{short_type_name(upgrade_type)}")
                            continue
                        name = mod_data["n"]
                        maximum = int(as_number(mod_data.get("mx")) or 0)
                    if not direct_type_reference:
                        fp = fingerprint(upgrade.get("UpgradeFingerprint"))
                        raw_rank = as_number((fp or {}).get("lvl"))
                        rank = int(raw_rank) if raw_rank is not None else None
                    if rank is None:
                        issues.append(f"{name}：{direct_rank_issue or '背包快照没有该 Mod 的等级；当前未带入'}")
                        continue
                    if rank != maximum:
                        issues.append(f"{name}：快照记录为等级 {rank}/{maximum}；当前导入器只带入满级条目")
                        continue
                    slots[slot] = name

                configs.append({
                    "l": config_label(config_index),
                    "s": slots,
                    "r": riven,
                    "rs": riven_slot,
                    "exact": not issues,
                    "issues": issues,
                })

            result.append({
                "id": opaque_id,
                "n": calc_name,
                "z": display_name,
                "c": calculator_category,
                "k": inventory_category,
                "p": progenitor_elements(weapon),
                "inc": incarnon,
                "cfg": configs,
            })

    result.sort(key=lambda row: ((row.get("z") or "").casefold(), row["id"]))
    return result


# ---- 战甲、战甲配置与整套军械库 ---------------------------------------------


def opaque_instance_id(item: dict, inventory_category: str, ordinal: int) -> str:
    """Stable app-only id for one account item, never the DE instance id."""
    item_type = item.get("ItemType") if isinstance(item, dict) else None
    raw = object_id(item.get("ItemId")) if isinstance(item, dict) else None
    raw = raw or f"{inventory_category}:{ordinal}:{item_type or ''}"
    return sha256(raw.encode("utf-8"))[:20]


def _rows_by_unique_name(path: str) -> dict[str, dict]:
    """Load Aleca's public game-data rows without making them an app runtime API."""
    if not os.path.exists(path):
        return {}
    try:
        rows = load_json(path)
    except (OSError, ValueError, json.JSONDecodeError):
        return {}
    if not isinstance(rows, list):
        return {}
    return {
        row["uniqueName"]: row
        for row in rows
        if isinstance(row, dict) and isinstance(row.get("uniqueName"), str)
    }


def frame_static_catalogues() -> tuple[dict[str, dict], dict[str, dict], dict[str, dict], dict[str, dict]]:
    """Return only static game definitions used while *building* the payload.

    Warframes.json / Mods.json / Arcanes.json are AlecaFrame's local data files,
    not a login or process-memory source.  The mobile payload copies only the
    names, ranks, equipped slots, and concise strength terms needed by the
    UI; no raw account identifiers or arbitrary cache records are exported.
    """
    game_data = load_json(GAMEDATA)
    game_mods = game_data.get("mods") if isinstance(game_data, dict) else {}
    game_mods = game_mods if isinstance(game_mods, dict) else {}
    local_mods = _rows_by_unique_name(ALECA_MODS)
    arcanes = _rows_by_unique_name(ALECA_ARCANES)
    frames = _rows_by_unique_name(ALECA_WARFRAMES)
    return game_mods, local_mods, arcanes, frames


def upgrade_indexes(inv: dict) -> tuple[dict[str, dict], dict[str, list[dict]]]:
    by_id: dict[str, dict] = {}
    by_type: dict[str, list[dict]] = {}
    for raw in inv.get("Upgrades") or []:
        if not isinstance(raw, dict):
            continue
        item_id = object_id(raw.get("ItemId"))
        if item_id:
            by_id[item_id] = raw
        item_type = raw.get("ItemType")
        if isinstance(item_type, str) and item_type:
            by_type.setdefault(item_type, []).append(raw)
    return by_id, by_type


def resolve_config_upgrade(reference: str, upgrades: dict[str, dict],
                           upgrades_by_type: dict[str, list[dict]]) -> tuple[dict | None, int | None, str | None]:
    """Resolve one equipped upgrade and its actual rank.

    A Config sometimes contains a literal item-type path rather than an owned
    card instance.  The path proves which card is equipped but not which copy.
    We recover a rank only when every owned copy has the same rank.  Otherwise
    the exported config remains visible but its strength contribution is not
    fabricated as max rank.
    """
    if reference.startswith("/"):
        item_type = reference
        candidate_ranks = {
            int(raw_rank)
            for candidate in upgrades_by_type.get(item_type, [])
            for raw_rank in [as_number((fingerprint(candidate.get("UpgradeFingerprint")) or {}).get("lvl"))]
            if raw_rank is not None
        }
        if len(candidate_ranks) == 1:
            return {"ItemType": item_type}, next(iter(candidate_ranks)), None
        if not candidate_ranks:
            return {"ItemType": item_type}, None, (
                "配置只记录了升级类型，背包中没有可确定等级的同名卡"
            )
        ranks = "/".join(str(value) for value in sorted(candidate_ranks))
        return {"ItemType": item_type}, None, (
            f"配置只记录了升级类型，而背包中同名卡的等级为 {ranks}"
        )

    upgrade = upgrades.get(reference)
    if not isinstance(upgrade, dict):
        return None, None, "此槽引用的升级在背包快照中找不到"
    fp = fingerprint(upgrade.get("UpgradeFingerprint"))
    raw_rank = as_number((fp or {}).get("lvl"))
    rank = int(raw_rank) if raw_rank is not None else None
    if rank is None:
        return upgrade, None, "该升级在背包快照中没有等级"
    return upgrade, rank, None


def local_rank_stats(meta: dict, rank: int | None) -> list[str]:
    """Return the exact rank's display lines from the local static catalogue."""
    if rank is None:
        return []
    rows = meta.get("levelStats") if isinstance(meta.get("levelStats"), list) else None
    if rows is not None:
        if not (0 <= rank < len(rows)) or not isinstance(rows[rank], dict):
            return []
        stats = rows[rank].get("stats")
        return [value for value in stats if isinstance(value, str)] if isinstance(stats, list) else []

    rows = meta.get("lv") if isinstance(meta.get("lv"), list) else None
    if rows is None or not (0 <= rank < len(rows)):
        return []
    return [value for value in rows[rank] if isinstance(value, str)] if isinstance(rows[rank], list) else []


def compact_stat_line(value: str) -> str:
    # The local descriptions contain markup such as <LOWER_IS_BETTER>.
    # Keep human text, but do not leak renderer tokens into the app.
    value = re.sub(r"<[^>]+>", "", value.replace("\\n", " "))
    return re.sub(r"\s+", " ", value).strip()


_PLAIN_STRENGTH = re.compile(r"^([+-]?\d+(?:\.\d+)?)%\s+Ability Strength$", re.IGNORECASE)
_FOURTH_ABILITY_STRENGTH = re.compile(
    r"^([+-]?\d+(?:\.\d+)?)%\s+Ability Strength for your 4th Ability$", re.IGNORECASE
)
_PERSONAL_STRENGTH_LOSS = re.compile(
    r"^You lose .*?(\d+(?:\.\d+)?)%\s+Ability Strength", re.IGNORECASE
)
_WEAPON_BUFF_PERCENT = re.compile(
    r"\badditional\s+(\d+(?:\.\d+)?)%.*?\bDamage\s+to\s+their\s+attacks\b",
    re.IGNORECASE,
)


def weapon_buff_scale_from_stats(upgrade_name: str, stats: list[str]) -> float | None:
    """Return this equipped augment's exact weapon-buff ratio.

    DamageKit's compact action table stores Shock Trooper and Venom Dose at
    their max-rank coefficient of 1.0.  A Config, however, can contain a
    lower-ranked copy.  Export the number printed on *that exact rank* so the
    iOS client can multiply the action rather than silently promoting it to
    max rank.  This is intentionally limited to the two actions currently
    represented in DamageKit; other Augments remain visible but do not acquire
    a guessed calculation rule.
    """
    if upgrade_name not in {"Shock Trooper", "Venom Dose"}:
        return None
    for raw in stats:
        for fragment in raw.replace("\\n", "\n").splitlines():
            line = compact_stat_line(fragment)
            match = _WEAPON_BUFF_PERCENT.search(line)
            if match:
                return float(match.group(1)) / 100
    return None


def strength_terms_from_stats(stats: list[str]) -> tuple[list[dict], list[str]]:
    """Extract only unconditionally exact Ability-Strength terms.

    Every other line that mentions Ability Strength is retained in `review`.
    It is deliberately *not* promoted to a guessed passive bonus: stacks,
    next-cast effects, health thresholds, and squad auras each need their own
    game-state control in the client.
    """
    terms: list[dict] = []
    review: list[str] = []
    for raw in stats:
        for fragment in raw.replace("\\n", "\n").splitlines():
            line = compact_stat_line(fragment)
            if not line or "ability strength" not in line.lower():
                continue
            match = _PLAIN_STRENGTH.fullmatch(line)
            if match:
                value = float(match.group(1)) / 100
                terms.append({"l": f"{value * 100:+g}% 技能强度", "v": value, "k": "base"})
                continue
            match = _FOURTH_ABILITY_STRENGTH.fullmatch(line)
            if match:
                value = float(match.group(1)) / 100
                terms.append({
                    "l": f"第 4 技能 {value * 100:+g}% 技能强度",
                    "v": value,
                    "k": "ability4",
                })
                continue
            match = _PERSONAL_STRENGTH_LOSS.match(line)
            if match:
                value = -float(match.group(1)) / 100
                terms.append({"l": f"{value * 100:+g}% 技能强度", "v": value, "k": "base"})
                continue
            review.append(line)
    # One display string can occur in a row twice because a static cache keeps
    # historical rank data.  It is still one equipped card term.
    deduped_review = list(dict.fromkeys(review))
    return terms, deduped_review


def local_language_rows() -> dict[str, dict]:
    """Return Aleca's local translated static names when that cache exists.

    This is not an account-data source and never becomes a mobile runtime
    dependency.  It only turns a static ItemType path into the name already
    shown by the game/Aleca cache while the local payload is being built.
    """
    if not os.path.exists(ALECA_LANG):
        return {}
    try:
        rows = load_json(ALECA_LANG)
    except (OSError, ValueError, json.JSONDecodeError):
        return {}
    return rows if isinstance(rows, dict) else {}


def localized_item_name(item: dict, inventory_category: str, ordinal: int,
                        display_rows: dict[str, list[dict]], lang: dict[str, dict]) -> str:
    """Choose a human name without exporting the raw DE item path.

    A named MOA can have an ItemName in the account snapshot.  That is the
    player's visible companion name, so prefer it.  For normal equipment use
    the local Chinese static table, then the already-derived view row, and
    finally a safe tail-only diagnostic label.
    """
    raw_name = item.get("ItemName") if isinstance(item, dict) else None
    if isinstance(raw_name, str) and raw_name.strip():
        # Companion names can be encoded as
        # `/Lotus/Language/Pets/...|VISIBLE NAME`.  The left part is a
        # localization key, not a label the player should ever see.
        visible_name = raw_name.rsplit("|", 1)[-1].strip()
        if visible_name and not visible_name.startswith("/"):
            return visible_name

    item_type = item.get("ItemType") if isinstance(item, dict) else None
    if isinstance(item_type, str) and item_type:
        entry = lang.get(item_type)
        if isinstance(entry, dict):
            for language in ("zh", "tc"):
                locale = entry.get(language)
                name = locale.get("name") if isinstance(locale, dict) else None
                if isinstance(name, str) and name.strip():
                    return name.strip()

    rows = display_rows.get(inventory_category) or []
    display = rows[ordinal] if ordinal < len(rows) else {}
    name = display.get("zh") if isinstance(display, dict) else None
    if isinstance(name, str) and name.strip():
        return name.strip()
    return short_type_name(item_type) if isinstance(item_type, str) else "未命名装备"


def equipment_upgrade_metadata(upgrade_type: str, game_mods: dict[str, dict],
                               local_mods: dict[str, dict], arcanes: dict[str, dict]) -> tuple[str, int | None, str]:
    """Resolve an equipped Mod/Arcane name and its catalogue maximum rank.

    This function does not decide whether the rank is usable in a damage
    formula.  It simply preserves the exact source configuration for the
    equipment-inspection UI, including lower-ranked cards.
    """
    game_meta = game_mods.get(upgrade_type)
    local_meta = local_mods.get(upgrade_type) or arcanes.get(upgrade_type) or {}
    game_meta = game_meta if isinstance(game_meta, dict) else {}
    local_meta = local_meta if isinstance(local_meta, dict) else {}
    name = game_meta.get("n") if isinstance(game_meta.get("n"), str) else None
    name = name or local_meta.get("name") or short_type_name(upgrade_type)
    maximum = as_number(game_meta.get("mx"))
    if maximum is None:
        maximum = as_number(local_meta.get("fusionLimit"))
    if maximum is None:
        levels = local_meta.get("levelStats")
        if isinstance(levels, list) and levels:
            maximum = len(levels) - 1
    local_type = str(local_meta.get("type") or "").lower()
    kind = "Arcane" if "arcane" in local_type or "arcane" in upgrade_type.lower() else "Mod"
    return name, int(maximum) if maximum is not None else None, kind


def build_equipment_configs(item: dict, upgrades: dict[str, dict],
                            upgrades_by_type: dict[str, list[dict]],
                            game_mods: dict[str, dict], local_mods: dict[str, dict],
                            arcanes: dict[str, dict]) -> list[dict]:
    """Export a non-weapon equipment body's A/B/C Mods and Arcanes exactly.

    Unlike a DamageKit weapon import, this function deliberately does not
    require every card to have a damage rule and never promotes an uncertain
    rank to max.  The result is an auditable configuration record for
    companions and Archwings.
    """
    raw_configs = item.get("Configs") if isinstance(item.get("Configs"), list) else []
    if not raw_configs:
        raw_configs = [{}]

    configs: list[dict] = []
    for config_index, raw_config in enumerate(raw_configs):
        config = raw_config if isinstance(raw_config, dict) else {}
        entries: list[dict] = []
        issues: list[str] = []
        raw_slots = config.get("Upgrades") if isinstance(config.get("Upgrades"), list) else []
        for slot, reference in enumerate(raw_slots):
            if not isinstance(reference, str) or not reference:
                continue
            upgrade, rank, rank_issue = resolve_config_upgrade(
                reference, upgrades, upgrades_by_type
            )
            if not isinstance(upgrade, dict):
                issues.append(f"第 {slot + 1} 槽：{rank_issue or '升级无法解析'}")
                continue
            upgrade_type = upgrade.get("ItemType")
            if not isinstance(upgrade_type, str) or not upgrade_type:
                issues.append(f"第 {slot + 1} 槽：升级没有类型信息")
                continue
            name, maximum, kind = equipment_upgrade_metadata(
                upgrade_type, game_mods, local_mods, arcanes
            )
            entry: dict = {"s": slot, "n": name, "r": rank, "k": kind}
            if maximum is not None:
                entry["m"] = maximum
            entries.append(entry)
            if rank_issue:
                issues.append(f"{name}：{rank_issue}")

        configs.append({
            "l": config_label(config_index),
            "u": entries,
            "exact": not issues,
            "issues": issues,
        })
    return configs


def build_owned_equipment(inv: dict, view: dict, categories: tuple[str, ...], *,
                          item_filter=None, output_category: str | None = None) -> list[dict]:
    """Export owned companion or Archwing bodies with their actual configs."""
    game_mods, local_mods, arcanes, _frames = frame_static_catalogues()
    upgrades, upgrades_by_type = upgrade_indexes(inv)
    lang = local_language_rows()
    display_rows: dict[str, list[dict]] = {}
    for row in view.get("gear") or []:
        if not isinstance(row, dict):
            continue
        category = row.get("cat")
        if isinstance(category, str):
            display_rows.setdefault(category, []).append(row)

    result: list[dict] = []
    for inventory_category in categories:
        for ordinal, item in enumerate(inv.get(inventory_category) or []):
            if not isinstance(item, dict):
                continue
            if item_filter is not None and not item_filter(item):
                continue
            item_type = item.get("ItemType")
            if not isinstance(item_type, str) or not item_type:
                continue
            result.append({
                "id": opaque_instance_id(item, inventory_category, ordinal),
                "z": localized_item_name(item, inventory_category, ordinal, display_rows, lang),
                "k": output_category or inventory_category,
                "cfg": build_equipment_configs(
                    item, upgrades, upgrades_by_type, game_mods, local_mods, arcanes
                ),
            })

    result.sort(key=lambda row: ((row.get("z") or "").casefold(), row["id"]))
    return result


def gear_stack_counts(inv: dict) -> dict[str, int]:
    """Return only quantities explicitly represented as inventory stacks."""
    result: dict[str, int] = {}
    for category in GEAR_STACK_CATEGORIES:
        for item in inv.get(category) or []:
            if not isinstance(item, dict):
                continue
            item_type = item.get("ItemType")
            count = as_number(item.get("ItemCount"))
            if not isinstance(item_type, str) or not item_type or count is None:
                continue
            result[item_type] = result.get(item_type, 0) + int(count)
    return result


def build_equipped_gear(inv: dict) -> list[dict]:
    """Export the source-ordered account gear wheel, not a fictional loadout."""
    lang = local_language_rows()
    counts = gear_stack_counts(inv)
    result: list[dict] = []
    for slot, item_type in enumerate(inv.get("EquippedGear") or []):
        if not isinstance(item_type, str) or not item_type:
            continue
        item = {"ItemType": item_type}
        row: dict = {
            "id": sha256(f"gear:{slot}:{item_type}".encode("utf-8"))[:20],
            "s": slot,
            "n": localized_item_name(item, "EquippedGear", slot, {}, lang),
        }
        if item_type in counts:
            row["c"] = counts[item_type]
        result.append(row)
    return result


def archon_shards(suit: dict) -> list[dict]:
    result: list[dict] = []
    raw_shards = suit.get("ArchonCrystalUpgrades")
    if not isinstance(raw_shards, list):
        return result
    for slot, raw in enumerate(raw_shards):
        if not isinstance(raw, dict):
            continue
        item_type = raw.get("UpgradeType")
        if not isinstance(item_type, str) or not item_type:
            continue
        key = short_type_name(item_type)
        known = ARCHON_SHARD_EFFECTS.get(key)
        row: dict = {
            "s": slot,
            "n": known.get("name") if known else f"执政官石 · {key}",
        }
        if known and isinstance(known.get("abilityStrength"), (int, float)):
            row["as"] = known["abilityStrength"]
        if known and isinstance(known.get("damageKitName"), str):
            row["dk"] = known["damageKitName"]
        if key.endswith("Mythic"):
            row["tau"] = True
        result.append(row)
    return result


def build_owned_warframes(inv: dict, view: dict) -> list[dict]:
    """Export owned Warframe instances with their real A/B/C configuration.

    This is intentionally separate from `build_owned_weapons`: a Warframe is
    not a generic percentage field.  Its Mod ranks, its Archon Shards, and a
    Helminth override are all source data for later ability resolution.
    """
    game_mods, local_mods, arcanes, frame_defs = frame_static_catalogues()
    upgrades, upgrades_by_type = upgrade_indexes(inv)

    display_rows = [row for row in view.get("gear") or []
                    if isinstance(row, dict) and row.get("cat") == "Suits"]
    ability_by_path: dict[str, dict] = {}
    for frame in frame_defs.values():
        for ability in frame.get("abilities") or []:
            if isinstance(ability, dict) and isinstance(ability.get("uniqueName"), str):
                ability_by_path.setdefault(ability["uniqueName"], ability)

    result: list[dict] = []
    for ordinal, suit in enumerate(inv.get("Suits") or []):
        if not isinstance(suit, dict):
            continue
        item_type = suit.get("ItemType")
        if not isinstance(item_type, str) or not item_type:
            continue
        frame_def = frame_defs.get(item_type, {})
        display = display_rows[ordinal] if ordinal < len(display_rows) else {}
        name = display.get("zh") if isinstance(display.get("zh"), str) else None
        name = name or frame_def.get("name") or short_type_name(item_type)

        abilities = []
        for ability_index, ability in enumerate(frame_def.get("abilities") or [], start=1):
            if isinstance(ability, dict) and isinstance(ability.get("name"), str):
                abilities.append({"o": ability_index, "n": ability["name"]})

        configs: list[dict] = []
        raw_configs = suit.get("Configs") if isinstance(suit.get("Configs"), list) else []
        if not raw_configs:
            raw_configs = [{}]
        for config_index, raw_config in enumerate(raw_configs):
            config = raw_config if isinstance(raw_config, dict) else {}
            entries: list[dict] = []
            issues: list[str] = []
            raw_slots = config.get("Upgrades") if isinstance(config.get("Upgrades"), list) else []
            for slot, reference in enumerate(raw_slots):
                if not isinstance(reference, str) or not reference:
                    continue
                upgrade, rank, rank_issue = resolve_config_upgrade(reference, upgrades, upgrades_by_type)
                if not isinstance(upgrade, dict):
                    if rank_issue:
                        issues.append(f"第 {slot + 1} 槽：{rank_issue}")
                    continue
                upgrade_type = upgrade.get("ItemType")
                if not isinstance(upgrade_type, str) or not upgrade_type:
                    issues.append(f"第 {slot + 1} 槽：升级没有类型信息")
                    continue

                game_meta = game_mods.get(upgrade_type)
                local_meta = local_mods.get(upgrade_type) or arcanes.get(upgrade_type) or {}
                game_meta = game_meta if isinstance(game_meta, dict) else {}
                local_meta = local_meta if isinstance(local_meta, dict) else {}
                upgrade_name = game_meta.get("n") if isinstance(game_meta.get("n"), str) else None
                upgrade_name = upgrade_name or local_meta.get("name") or short_type_name(upgrade_type)
                maximum = as_number(game_meta.get("mx"))
                if maximum is None:
                    maximum = as_number(local_meta.get("fusionLimit"))
                if maximum is None:
                    levels = local_meta.get("levelStats")
                    if isinstance(levels, list) and levels:
                        maximum = len(levels) - 1
                stats = local_rank_stats(local_meta or game_meta, rank)
                strength_terms, strength_review = strength_terms_from_stats(stats)
                weapon_buff_scale = weapon_buff_scale_from_stats(upgrade_name, stats)
                kind = "Arcane" if "arcane" in str(local_meta.get("type") or "").lower() else "Mod"
                entry: dict = {
                    "s": slot,
                    "n": upgrade_name,
                    "r": rank,
                    "m": int(maximum) if maximum is not None else None,
                    "k": kind,
                }
                if strength_terms:
                    entry["st"] = strength_terms
                if strength_review:
                    entry["sr"] = strength_review
                if weapon_buff_scale is not None:
                    entry["wb"] = weapon_buff_scale
                entries.append(entry)
                if rank_issue:
                    issues.append(f"{upgrade_name}：{rank_issue}")

            helminth = None
            raw_override = config.get("AbilityOverride")
            if isinstance(raw_override, dict):
                raw_ability = raw_override.get("Ability")
                ability = ability_by_path.get(raw_ability) if isinstance(raw_ability, str) else None
                raw_index = as_number(raw_override.get("Index"))
                helminth = {
                    "o": int(raw_index) if raw_index is not None else None,
                    "n": ability.get("name") if isinstance(ability, dict) else short_type_name(raw_ability)
                    if isinstance(raw_ability, str) else "未识别的 Helminth 技能",
                }

            row: dict = {
                "l": config_label(config_index),
                "u": entries,
                "exact": not issues,
                "issues": issues,
            }
            if helminth:
                row["h"] = helminth
            configs.append(row)

        result.append({
            "id": opaque_instance_id(suit, "Suits", ordinal),
            "z": name,
            "a": abilities,
            "cfg": configs,
            "sh": archon_shards(suit),
        })

    result.sort(key=lambda row: ((row.get("z") or "").casefold(), row["id"]))
    return result


def build_loadouts(inv: dict, owned_warframes: list[dict], owned_weapons: list[dict],
                   owned_companions: list[dict], owned_companion_weapons: list[dict],
                   owned_archwings: list[dict]) -> list[dict]:
    """Export each DE preset family without pretending it is one global build.

    DE stores normal Arsenal, companion, and Archwing presets as separate
    lists.  We retain that boundary in `t`: the UI can put the four Arsenal
    areas on one page, but it must not invent a linkage the source did not
    provide.  Every slot points at an opaque imported instance ID.  If a
    preset references an absent instance (which happens in real snapshots),
    the slot contains a concrete source issue instead of a guessed weapon.
    """
    all_rows = (owned_warframes + owned_weapons + owned_companions
                + owned_companion_weapons + owned_archwings)
    names_by_id = {
        row["id"]: row.get("z")
        for row in all_rows
        if isinstance(row, dict) and isinstance(row.get("id"), str)
    }
    id_by_raw: dict[str, str] = {}
    category_specs = [
        ("Suits", None),
        *((category, None) for category in OWNED_WEAPON_CATEGORIES),
        *((category, None) for category in OWNED_COMPANION_CATEGORIES),
        *((category, None) for category in OWNED_ARCHWING_CATEGORIES),
        ("SpecialItems", is_companion_special_weapon),
    ]
    for category, item_filter in category_specs:
        for ordinal, item in enumerate(inv.get(category) or []):
            if not isinstance(item, dict):
                continue
            if item_filter is not None and not item_filter(item):
                continue
            raw = object_id(item.get("ItemId"))
            if raw:
                id_by_raw[raw] = opaque_instance_id(item, category, ordinal)

    current_ids = {
        value for value in (object_id(row) for row in inv.get("CurrentLoadOutIds") or [])
        if value
    }
    presets = inv.get("LoadOutPresets") if isinstance(inv.get("LoadOutPresets"), dict) else {}
    preset_specs = (
        ("NORMAL", "normal", [
            ("s", "warframe"), ("l", "primary"), ("p", "secondary"),
            ("m", "melee"), ("h", "heavy"),
        ]),
        ("SENTINEL", "companion", [
            ("s", "companion"), ("b", "companionWeapon"),
        ]),
        ("ARCHWING", "archwing", [
            ("s", "archwing"), ("l", "archgun"), ("m", "archmelee"),
        ]),
    )
    result: list[dict] = []
    for source_family, kind, role_keys in preset_specs:
        family_rows = presets.get(source_family) if isinstance(presets.get(source_family), list) else []
        for ordinal, preset in enumerate(family_rows):
            if not isinstance(preset, dict):
                continue
            raw_preset_id = object_id(preset.get("ItemId")) or f"{source_family}:{ordinal}"
            slots: list[dict] = []
            for key, role in role_keys:
                source = preset.get(key)
                if not isinstance(source, dict):
                    continue
                raw_item_id = object_id(source.get("ItemId"))
                opaque_id = id_by_raw.get(raw_item_id) if raw_item_id else None
                config_index = as_number(source.get("mod"))
                slot: dict = {"r": role, "i": opaque_id}
                if opaque_id and isinstance(names_by_id.get(opaque_id), str):
                    slot["z"] = names_by_id[opaque_id]
                elif raw_item_id:
                    slot["x"] = "账号快照引用的装备实例不在已导入的背包条目中"
                else:
                    slot["x"] = "账号快照的这个槽没有装备实例引用"
                if config_index is not None:
                    slot["c"] = int(config_index)
                if source.get("hide") is True:
                    slot["hide"] = True
                slots.append(slot)
            result.append({
                "id": sha256(f"{source_family}:{raw_preset_id}".encode("utf-8"))[:20],
                "n": preset.get("n") if isinstance(preset.get("n"), str) and preset.get("n") else f"配置 {ordinal + 1}",
                "t": kind,
                "fav": bool(preset.get("Favorite")),
                "active": raw_preset_id in current_ids,
                "slots": slots,
            })
    return result


def fetch_aya(*, offline: bool = False) -> dict:
    """当期 Varzia 的 Aya 遗物。拿不到就用上次缓存，不阻断构建。"""
    if offline:
        return load_json(CACHE) if os.path.exists(CACHE) else {"relics": [], "fetchedAt": None}
    try:
        req = urllib.request.Request(WS_URL, headers={
            "Accept": "application/json", "User-Agent": "WarframeWatch/1.0",
        })
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
            if resp.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            doc = json.loads(raw)
        vt = doc.get("vaultTrader") or {}
        rows = []
        for entry in vt.get("inventory") or []:
            # credits=1 且没有 ducats 的条目才是 Aya 换的遗物；其余是 Prime Vault 礼包
            if entry.get("ducats") is not None or entry.get("credits") != 1:
                continue
            rows.append({"ref": entry["uniqueName"], "item": entry.get("item") or ""})
        payload = {
            "fetchedAt": now_iso(),
            "activation": vt.get("activation"),
            "expiry": vt.get("expiry"),
            "character": vt.get("character"),
            "location": vt.get("location"),
            "relics": rows,
        }
        atomic_json_write(CACHE, payload)
        return payload
    except Exception as exc:                                    # noqa: BLE001
        print(f"  Aya 拉取失败（用缓存）：{exc}")
        if os.path.exists(CACHE):
            return load_json(CACHE)
        return {"relics": [], "fetchedAt": None}


def relic_id_zh(raw: str) -> str:
    """'Axi A18' → '后纪 A18'。页面上其余地方都用中文纪元，这里不能混。"""
    parts = raw.split()
    if len(parts) >= 2 and parts[0] in ERA_ZH:
        return f"{ERA_ZH[parts[0]]} {parts[1]}"
    return raw


def build(*, offline: bool = False) -> dict:
    view = load_json(VIEW)
    inv, _raw_snapshot, source = load_inventory_snapshot()
    items = {x["ref"]: x for x in load_json(MARKET_ITEMS)["items"] if x.get("ref")}
    prices = load_json(MARKET_PRICES)["items"]
    icons = load_json(ICONS) if os.path.exists(ICONS) else {"slugs": {}, "eras": {}}
    icons_by_slug = icons.get("slugs") or {}
    icons_by_era = icons.get("eras") or {}

    ducats = {}
    comp_path = os.path.join(ALECA, "Components.json")
    if os.path.exists(comp_path):
        for entry in load_json(comp_path):
            price = entry.get("primeSellingPrice")
            if price:
                ducats[entry["uniqueName"]] = price

    def quote(ref: str) -> dict:
        entry = items.get(ref) or items.get(alias_ref(ref) or "")
        if not entry:
            return {}
        return prices.get(entry["slug"]) or {}

    def icon(ref: str) -> dict:
        """`i` 是打包进 App 的图，`u` 是 CDN 相对路径（本地缺图时兜底）。"""
        entry = items.get(ref) or items.get(alias_ref(ref) or "")
        if not entry:
            return {}
        return icons_by_slug.get(entry["slug"]) or {}

    def pl(p: dict) -> int:
        """主口径：在线卖家的最低价。挂单里有人标 1p 钓鱼，sellMin 不可信。"""
        return p.get("sellOnline") or p.get("onlineMed") or 0

    def duc(ref: str) -> int:
        return ducats.get(ref) or ducats.get(alias_ref(ref) or "") or 0

    # ---- 套装
    sets = []
    # Sum every owned Prime component's price directly.  This is the only
    # inventory-wide Platinum headline; it never silently reserves a part for
    # an unfinished set.
    total_plat_all = 0
    total_loose = 0
    prime_part_units = 0
    priced_prime_part_units = 0
    # Both Ducat figures are useful, but they answer different questions.  The
    # old payload exposed only the reserve-aware value below and labelled it as
    # all exchangeable Ducats, which made it disagree with AlecaFrame.
    total_ducats_all = 0
    total_ducats_after_reserve = 0
    for s in view["sets"]:
        parts = []
        parts_value = 0
        loose = 0
        loose_ducats = 0
        for p in s["parts"]:
            q = quote(p["id"])
            unit = pl(q)
            parts_value += unit
            count = int(p.get("count") or 0)
            prime_part_units += count
            if unit > 0:
                priced_prime_part_units += count
                total_plat_all += count * unit
            # 已制成的套装，全部散件都能卖；未制成的要留一件
            sellable = count if s["status"] == "owned" else max(count - 1, 0)
            loose += sellable * unit
            unit_ducats = duc(p["id"])
            total_ducats_all += count * unit_ducats
            loose_ducats += sellable * unit_ducats
            parts.append({
                "l": p["label"],
                "n": count,
                "p": unit,
                "d": duc(p["id"]),
            })
        total_loose += loose
        total_ducats_after_reserve += loose_ducats
        pic = icon(s["id"])
        sets.append({
            "id": s["id"],
            "zh": s["zh"],
            "cat": s["cat"],
            "i": pic.get("a"),
            "u": pic.get("u"),
            "status": s["status"],
            "have": s["haveCount"],
            "total": s["total"],
            "parts": parts,
            "setPrice": pl(quote(s["id"])),
            "partsValue": parts_value,
            "loose": loose,
            "relics": [relic_id_zh(x) for x in (s.get("relics") or [])],
        })
    sets.sort(key=lambda x: (-x["loose"], x["zh"]))

    # ---- 遗物
    # view.json 的 stocks 以精炼档为键（Intact/Exceptional/Flawless/Radiant），
    # market 只按代号聚合，价格对四档通用。
    relics = []
    for r in view["relics"]:
        stocks = r.get("stocks") or {}
        st = {"I": int(stocks.get("Intact") or 0),
              "E": int(stocks.get("Exceptional") or 0),
              "F": int(stocks.get("Flawless") or 0),
              "R": int(stocks.get("Radiant") or 0)}
        relics_pic = icon(relic_ref_base(r.get("ref") or "")) if r.get("ref") else {}
        relics.append({
            "id": f'{r["eraZh"]} {r["code"]}',
            "era": r["eraZh"],
            "code": r["code"],
            "i": relics_pic.get("a"),
            "u": relics_pic.get("u"),
            "st": st,
            "n": r["total"],
            "p": pl(quote(relic_ref_base(r.get("ref") or ""))) if r.get("ref") else 0,
            "miss": r.get("setsMissing") or 0,
            "own": r.get("setsOwned") or 0,
        })
    relics.sort(key=lambda x: (-x["n"] * x["p"], x["id"]))

    # ---- 当期 Aya
    aya_doc = fetch_aya(offline=offline)
    by_relic_ref = {r["ref"]: r["id"] for r in view["relics"] if r.get("ref")}
    owned_ids = {r["id"] for r in view["relics"]}
    price_by_id = {r["id"]: r["p"] for r in relics}
    icon_by_id = {r["id"]: {"a": r["i"], "u": r["u"]} for r in relics}
    relic_names = load_relic_names()
    aya = []
    for row in aya_doc.get("relics") or []:
        rid = by_relic_ref.get(row["ref"]) or guess_relic_id(row["ref"], relic_names)
        # 这些遗物用户多半没有，价格得单独查（wf_market 会读 aya_cache.json 把它们加进目标）
        ref = relic_ref_base(row["ref"].replace("/StoreItems/", "/"))
        pic = icon(ref) or icon_by_id.get(rid) or {}
        if not pic.get("a") and rid:
            # Aya 卖的遗物不在背包里，按纪元退回同一张图
            era_key = {"古纪": "lith", "前纪": "meso", "中纪": "neo",
                       "后纪": "axi", "安魂": "requiem"}.get(rid[:2])
            pic = {"a": icons_by_era.get(era_key)} if era_key else {}
        aya.append({
            "id": rid or row["item"],
            "i": pic.get("a"),
            "u": pic.get("u"),
            "p": pl(quote(ref)),
            "owned": (rid in owned_ids) if rid else False,
        })

    # ---- 概况
    profile = {
        "mr": int(inv.get("PlayerLevel") or 0),
        "plat": int(inv.get("PremiumCreditsFree") or 0) + int(inv.get("PremiumCredits") or 0),
        "credits": int(inv.get("RegularCredits") or 0),
        "sync": source.get("accountSync"),
    }

    # Weapons and Warframes share the same snapshot and must be built before
    # loadout presets: a preset only transports opaque references to these
    # concrete account instances, never a DE ItemId.
    owned_weapons = build_owned_weapons(inv)
    owned_warframes = build_owned_warframes(inv, view)
    owned_companions = build_owned_equipment(inv, view, OWNED_COMPANION_CATEGORIES)
    owned_companion_weapons = build_owned_equipment(
        inv, view, ("SpecialItems",),
        item_filter=is_companion_special_weapon,
        output_category="CompanionWeapons",
    )
    owned_archwings = build_owned_equipment(inv, view, OWNED_ARCHWING_CATEGORIES)
    equipped_gear = build_equipped_gear(inv)
    counts = view["counts"]
    return {
        # Kept for old bundled samples.  It is no longer used to decide which
        # snapshot wins: that decision is the immutable manifest hash.
        "builtAt": source.get("accountSync") or "1970-01-01T00:00:00Z",
        "source": {
            "accountHash": source["accountHash"],
            "accountSync": source.get("accountSync"),
        },
        "marketAt": load_json(MARKET_PRICES).get("ts"),
        "profile": profile,
        "totals": {
            "setsOwned": sum(1 for s in sets if s["status"] == "owned"),
            "setsReady": sum(1 for s in sets if s["status"] == "ready"),
            "setsClose": sum(1 for s in sets if s["status"] == "missing" and s["loose"] == 0
                             and s["total"] - s["have"] <= 2),
            "setsAll": len(sets),
            # Sum(count × listed online price) for every owned Prime component.
            # Components without an online quote stay visible through the two
            # coverage counts below; they are not fabricated as 0p values.
            "allPlat": total_plat_all,
            "primePartUnits": prime_part_units,
            "pricedPrimePartUnits": priced_prime_part_units,
            # Retained only as a separate "sell surplus" comparison.  This
            # value intentionally keeps one copy for every uncrafted set.
            "loosePlat": total_loose,
            # All owned Prime parts, matching AlecaFrame's exchange total.
            "allDucats": total_ducats_all,
            # Keep one copy of each required part for every uncrafted set.
            # Retained under its old field name for old clients.
            "looseDucats": total_ducats_after_reserve,
            "relicKinds": counts["relicKinds"],
            "relicUnits": counts["relics"],
            "mods": counts["modStacks"],
        },
        "aya": {
            "activation": aya_doc.get("activation"),
            "expiry": aya_doc.get("expiry"),
            "location": aya_doc.get("location"),
            "items": aya,
        },
        "sets": sets,
        "relics": relics,
        "ownedWeapons": owned_weapons,
        "ownedWarframes": owned_warframes,
        "ownedCompanions": owned_companions,
        "ownedCompanionWeapons": owned_companion_weapons,
        "ownedArchwings": owned_archwings,
        "equippedGear": equipped_gear,
        "loadouts": build_loadouts(
            inv, owned_warframes, owned_weapons, owned_companions,
            owned_companion_weapons, owned_archwings,
        ),
    }


def load_relic_names() -> dict:
    """uniqueName → '前纪 S15'。Aya 卖的是 Vault 遗物，名字在 Relics.json 里。"""
    path = os.path.join(ALECA, "Relics.json")
    if not os.path.exists(path):
        return {}
    out = {}
    for r in load_json(path):
        name = r.get("name") or ""
        parts = name.split()
        if len(parts) >= 2 and parts[0] in ERA_ZH:
            out[r["uniqueName"]] = f"{ERA_ZH[parts[0]]} {parts[1]}"
    return out


def guess_relic_id(ref: str, names: dict[str, str]) -> str | None:
    """Aya 商店的 ref 带 `/StoreItems/`，Relics.json 里不带，先归一化再查。"""
    for candidate in (ref, ref.replace("/StoreItems/", "/")):
        hit = names.get(candidate)
        if hit:
            return hit
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=OUT, help="输出路径；默认写入 App 资源")
    parser.add_argument("--offline", action="store_true",
                        help="不访问 warframestat；Aya 只用已有本地缓存")
    args = parser.parse_args(argv)

    if not os.path.exists(MARKET_PRICES):
        print("没有价格快照，先跑 `wf_market.py sync`", file=sys.stderr)
        return 1

    # view 是同一份账号快照的派生物。它比 latest.json.gz 旧时，停止而不是用旧
    # 资产列表重新打一个“新”版本；真正的版本身份则由发布清单的 payload hash 决定。
    if os.path.exists(SNAPSHOT) and os.path.exists(VIEW):
        if os.path.getmtime(VIEW) + 60 < os.path.getmtime(SNAPSHOT):
            print(
                "view.json 比背包快照旧：build_inventory_view.py 没有重跑？"
                f"\n  view.json   {datetime.fromtimestamp(os.path.getmtime(VIEW)):%Y-%m-%d %H:%M:%S}"
                f"\n  快照        {datetime.fromtimestamp(os.path.getmtime(SNAPSHOT)):%Y-%m-%d %H:%M:%S}",
                file=sys.stderr,
            )
            return 1

    data = build(offline=args.offline)
    atomic_json_write(args.out, data)
    size = os.path.getsize(args.out)

    t = data["totals"]
    print(f"套装 {t['setsAll']}（已制成 {t['setsOwned']} / 可制造 {t['setsReady']}）")
    print(f"全部已报价 Prime 散件市价 {t['allPlat']} p"
          f"（覆盖 {t['pricedPrimePartUnits']}/{t['primePartUnits']} 件；"
          f"保留一套后的余件参考 {t['loosePlat']} p）")
    print(f"全部可换 {t['allDucats']} Ducats（保留一套后 {t['looseDucats']}）")
    print(f"遗物 {t['relicKinds']} 代号 {t['relicUnits']} 个 · Aya {len(data['aya']['items'])} 项")
    print(f"背包武器 {len(data['ownedWeapons'])} 把 · 账号快照 {data['source']['accountHash'][:12]}")
    print(f"同伴本体 {len(data['ownedCompanions'])} · 同伴武器 {len(data['ownedCompanionWeapons'])}"
          f" · Archwing {len(data['ownedArchwings'])} · 装备轮 {len(data['equippedGear'])}")
    print(f"-> {args.out}  {size//1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
