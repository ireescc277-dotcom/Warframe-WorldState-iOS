#!/usr/bin/env python3
"""Build a standalone HTML viewer for the decrypted inventory.

Six ways of looking at the same snapshot, because the interesting question
changes with the tab: what am I worth, which relics do I still hold and what do
they drop, what have I mastered, which mods do I even own, where am I rich, and
which nodes have I unlocked.

Everything is inlined into one file — no fetch, no server, opens from disk.
Data comes from `wf_inventory.py`'s snapshot plus AlecaFrame's own dictionaries
(Chinese names, mod metadata, relic drop tables, star-chart node names).

    python scripts/build_inventory_view.py
    open data/inventory/view.html
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT = os.path.join(ROOT, "data", "inventory", "latest.json.gz")
OUT = os.path.join(ROOT, "data", "inventory", "view.html")
ALECA = os.path.join(os.environ.get("LOCALAPPDATA", ""), "AlecaFrame", "cachedData")

REFINE = ("Intact", "Exceptional", "Flawless", "Radiant")
REFINE_ZH = {"Intact": "完整", "Exceptional": "优良", "Flawless": "无瑕", "Radiant": "光辉"}
ERA_ZH = {"Lith": "古纪", "Meso": "前纪", "Neo": "中纪", "Axi": "后纪", "Requiem": "安魂", "Void": "虚空"}
ERA_ORDER = ["Lith", "Meso", "Neo", "Axi", "Requiem", "Void"]

GEAR_KEYS = (
    "Suits", "LongGuns", "Pistols", "Melee", "SpaceSuits", "SpaceGuns",
    "SpaceMelee", "Sentinels", "SentinelWeapons", "MoaPets", "KubrowPets",
    "OperatorAmps", "OperatorSuits", "MechSuits", "Ships", "CrewShips",
    "CrewMembers", "Horses", "Motorcycles", "DataKnives", "Scoops",
)

# 套装组成的权威来源是装备字典里的 components[]，不是从部件名反推。
# 只取 isPrime 的条目：Excalibur Umbra 这类非 Prime 套装也带 components，
# 但它们的构成里混着合金板、Kuva 这些制造材料，混进来会把"凑齐"算错。
PRIME_FILES = (
    ("Warframes.json", "战甲"),
    ("Primary.json", "主武器"),
    ("Secondary.json", "副手"),
    ("Melee.json", "近战"),
    ("Sentinels.json", "守护"),
    ("SentinelWeapons.json", "守护武器"),
    ("Arch-Gun.json", "空战枪"),
    ("Arch-Melee.json", "空战近战"),
    ("Archwing.json", "空战甲"),
    ("Pets.json", "宠物"),
)

# lang.json 对大部分部件给了中文（"机体"、"枪管"），但 Blueprint 一律是 null。
PART_ZH = {
    "Blueprint": "蓝图", "Chassis": "机体", "Neuroptics": "头部神经光元",
    "Systems": "系统", "Barrel": "枪管", "Receiver": "机匣", "Stock": "枪托",
    "Handle": "握柄", "Blade": "刀刃", "Blades": "刀刃", "Grip": "握把",
    "String": "弓弦", "Upper Limb": "上弓臂", "Lower Limb": "下弓臂",
    "Link": "连接件", "Gauntlet": "护手", "Hilt": "剑柄", "Chain": "链条",
    "Disc": "圆盘", "Head": "头部", "Pouch": "袋", "Stars": "星镖",
    "Wings": "翼", "Motor": "马达", "Rivet": "铆钉", "Core": "核心",
    "Ornament": "装饰", "Buckle": "扣环", "Band": "环带", "Plate": "板",
    "Grip Guard": "护手", "Tassel": "流苏", "Lens": "镜片",
}
GEAR_ZH = {
    "Suits": "战甲", "LongGuns": "主武器", "Pistols": "副手", "Melee": "近战",
    "SpaceSuits": "空战甲", "SpaceGuns": "空战枪", "SpaceMelee": "空战近战",
    "Sentinels": "守护", "SentinelWeapons": "守护武器", "MoaPets": "恐鸟",
    "KubrowPets": "库狛", "OperatorAmps": "增幅器", "OperatorSuits": "指挥官",
    "MechSuits": "殁世机甲", "Ships": "轨道飞行器", "CrewShips": "航道星舰",
    "CrewMembers": "船员", "Horses": "绝灵骥", "Motorcycles": "原子摩托车",
    "DataKnives": "数据刀", "Scoops": "捕获器",
}

# Gear entries are unique per instance: one row, no stack count, progress lives
# in XPInfo keyed by the same ItemType. XP is carried as a raw number on purpose:
# Kuva/Tenet weapons and Necramechs cap at 40 while everything else caps at 30,
# so any "is it maxed" verdict computed from a single threshold would be wrong
# for a whole class of gear.


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_solnodes():
    """solNodes.json ships with // comments, so it needs stripping first."""
    path = os.path.join(ALECA, "custom", "solNodes.json")
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    raw = re.sub(r"^\s*//.*$", "", raw, flags=re.M)
    return json.loads(raw)


def zh_of(lang, unique_name):
    entry = lang.get(unique_name) or {}
    node = entry.get("zh") or entry.get("tc") or {}
    return node.get("name")


def short_name(item_type):
    tail = item_type.rstrip("/").rsplit("/", 1)[-1]
    tail = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", tail)
    tail = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", " ", tail)
    return tail.replace("_", " ").strip()


def part_alias(pid):
    """`...ChassisComponent` <-> `...ChassisBlueprint`.

    套装的 components[] 用 Component 后缀，遗物的掉落表用 Blueprint 后缀，
    指的是同一件部件。只认一种写法会漏掉一半。
    """
    for suffix, other in (("Component", "Blueprint"), ("Blueprint", "Component")):
        if pid.endswith(suffix):
            return pid[: -len(suffix)] + other
    return None


def relic_key(name):
    """'Lith C10 Intact' -> ('Lith', 'C10', 'Intact').

    Requiem relics have no refinement tier at all; their name ends in 'Relic'.
    """
    m = re.match(r"^(\w+)\s+(\S+)\s+(Intact|Exceptional|Flawless|Radiant)$", name or "")
    if m:
        return m.group(1), m.group(2), m.group(3)
    m = re.match(r"^(\w+)\s+(\S+)\s+Relic$", name or "")
    if m:
        return m.group(1), m.group(2), "Intact"
    parts = (name or "").split()
    if len(parts) >= 3:
        return parts[0], parts[1], parts[-1]
    return None, name or "", "Intact"


def build(snapshot_path=SNAPSHOT):
    inv = json.loads(gzip.open(snapshot_path).read())
    base = os.path.join(ALECA, "json")
    lang = load_json(os.path.join(base, "lang.json"))
    mods_doc = load_json(os.path.join(base, "Mods.json"))
    relics_doc = load_json(os.path.join(base, "Relics.json"))
    node_doc = load_json(os.path.join(base, "Node.json"))
    solnodes = load_solnodes()

    mods_by_name = {m["uniqueName"]: m for m in mods_doc}
    relics_by_name = {r["uniqueName"]: r for r in relics_doc}
    nodes_by_tag = {}
    for entry in solnodes.items():
        tag, payload = entry
        nodes_by_tag[tag] = {"label": payload.get("value", tag), "type": payload.get("type")}
    for entry in node_doc:
        tag = entry.get("uniqueName", "")
        if tag:
            info = nodes_by_tag.setdefault(tag, {})
            info.setdefault("name", entry.get("name"))
            info["planet"] = entry.get("systemName")
            info.setdefault("type", entry.get("type"))

    # --- 拥有集合，用来判断遗物掉落里哪些已经有 ---
    stacks = {}
    for key in ("MiscItems", "Recipes", "Consumables", "Resources", "SpecialItems",
                "FlavourItems", "ShipDecorations", "WeaponSkins"):
        for entry in inv.get(key, []) or []:
            item_type = entry.get("ItemType")
            if item_type:
                count = entry.get("ItemCount")
                stacks[item_type] = stacks.get(item_type, 0) + (1 if count is None else int(count))

    xp_by_type = {}
    for entry in inv.get("XPInfo", []) or []:
        item_type = entry.get("ItemType")
        if item_type:
            xp_by_type[item_type] = xp_by_type.get(item_type, 0) + int(entry.get("XP") or 0)

    gear = []
    for key in GEAR_KEYS:
        for entry in inv.get(key, []) or []:
            item_type = entry.get("ItemType")
            if not item_type:
                continue
            xp = xp_by_type.get(item_type, 0)
            gear.append({
                "cat": key,
                "zh": zh_of(lang, item_type) or short_name(item_type),
                "en": short_name(item_type),
                "xp": xp,
            })
    owned = set(stacks) | {e.get("ItemType") for k in GEAR_KEYS
                           for e in (inv.get(k) or []) if e.get("ItemType")}

    # --- Prime 套装：部件清单来自装备字典，持有状态要用"成品也算" ---
    #
    # 同一个部件在两种 ID 形态下出现：套装 components 里是 ...ChassisComponent，
    # 遗物掉落表里是 ...ChassisBlueprint。两者是同一件东西，只查一边会漏一半。
    def part_count(pid):
        total = stacks.get(pid, 0)
        alias = part_alias(pid)
        if alias:
            total += stacks.get(alias, 0)
        return total

    part2set = {}
    prime_sets = []
    for fname, cat_zh in PRIME_FILES:
        path = os.path.join(base, fname)
        if not os.path.exists(path):
            continue
        for entry in load_json(path):
            if not entry.get("isPrime"):
                continue
            sid = entry.get("uniqueName")
            # 只留 /Recipes/ 路径的，Orokin Cell / Kuva / 合金板这些材料自动出局
            comps = [c for c in (entry.get("components") or [])
                     if "/Recipes/" in (c.get("uniqueName") or "")]
            if not sid or not comps:
                continue
            rows = []
            for comp in comps:
                pid = comp["uniqueName"]
                label = comp.get("name") or short_name(pid)
                zh = zh_of(lang, pid)
                if not zh or len(zh) > 10:
                    zh = PART_ZH.get(label, label)
                rows.append({
                    "label": zh,
                    "en": label,
                    "id": pid,
                    "count": part_count(pid),
                })
                for alias_pid in (pid, part_alias(pid)):
                    if alias_pid:
                        part2set[alias_pid] = sid
            prime_sets.append({
                "id": sid,
                "name": entry.get("name") or short_name(sid),
                "zh": zh_of(lang, sid) or entry.get("name") or short_name(sid),
                "cat": cat_zh,
                "crafted": sid in owned,
                "parts": rows,
            })

    # --- 遗物：按代号聚合四档持有量 ---
    relic_groups = {}
    for item_type, count in stacks.items():
        if "/Projections/" not in item_type:
            continue
        doc = relics_by_name.get(item_type)
        era, code, refine = relic_key(doc.get("name") if doc else short_name(item_type))
        if not era:
            continue
        gid = f"{era} {code}"
        group = relic_groups.get(gid)
        if group is None:
            group = {
                "id": gid,
                "era": era,
                "eraZh": ERA_ZH.get(era, era),
                "code": code,
                "zh": zh_of(lang, item_type) or f"{ERA_ZH.get(era, era)} {code} 遗物",
                "vaulted": bool(doc.get("vaulted")) if doc else False,
                "stocks": {r: 0 for r in REFINE},
                # market 按代号聚合、不带精炼档，查价时随便挑一个 uniqueName 即可
                "ref": item_type,
                "rewards": [],
                "owned": 0,
                "total": 0,
            }
            relic_groups[gid] = group
        if refine in group["stocks"]:
            group["stocks"][refine] += count
        group["owned"] += count

        if doc and not group["rewards"] and refine == "Intact":
            for reward in doc.get("rewards", []):
                item = reward.get("item") or {}
                # lang.json 对 Prime 部件只给"枪管""握柄"这种类型名，脱离武器名
                # 就无法区分是哪个武器的，所以短名直接弃用，退回英文全名。
                zh = zh_of(lang, item.get("uniqueName"))
                if zh and len(zh) < 5:
                    zh = None
                group["rewards"].append({
                    "zh": zh or item.get("name"),
                    "en": item.get("name"),
                    "chance": reward.get("chance"),
                    "rarity": reward.get("rarity"),
                    "have": item.get("uniqueName") in owned or item.get("uniqueName") in stacks,
                    "set": part2set.get(item.get("uniqueName")),
                })

    # 没有 Intact 只有别的档位时，掉落表会是空的，补一次
    for group in relic_groups.values():
        if group["rewards"]:
            continue
        for item_type, doc in relics_by_name.items():
            era, code, _ = relic_key(doc.get("name"))
            if f"{era} {code}" != group["id"]:
                continue
            for reward in doc.get("rewards", []):
                item = reward.get("item") or {}
                zh = zh_of(lang, item.get("uniqueName"))
                if zh and len(zh) < 5:
                    zh = None
                group["rewards"].append({
                    "zh": zh or item.get("name"),
                    "en": item.get("name"),
                    "chance": reward.get("chance"),
                    "rarity": reward.get("rarity"),
                    "have": item.get("uniqueName") in owned or item.get("uniqueName") in stacks,
                    "set": part2set.get(item.get("uniqueName")),
                })
            break

    relics = sorted(relic_groups.values(),
                    key=lambda g: (ERA_ORDER.index(g["era"]) if g["era"] in ERA_ORDER else 99,
                                   g["code"]))
    for group in relics:
        group["total"] = sum(group["stocks"].values())

    # --- 套装收尾：缺口、状态、以及"哪张遗物能出它" ---
    set_by_id = {s["id"]: s for s in prime_sets}
    for group in relics:
        for reward in group["rewards"]:
            sid = reward.get("set")
            target = set_by_id.get(sid)
            if target is None:
                reward["set"] = None
                reward["setOwned"] = None
                continue
            reward["set"] = target["zh"]
            # 刷遗物时真正要判断的是"这套我有没有"，散件持有与否反而是噪音
            reward["setOwned"] = bool(target["crafted"])
            target.setdefault("relics", set()).add(group["id"])

    # 一张遗物值不值得开，看的是"它能出的套装里还有几套我没有"
    for group in relics:
        sets_missing = {r["set"] for r in group["rewards"]
                        if r.get("set") and not r.get("setOwned")}
        sets_owned = {r["set"] for r in group["rewards"] if r.get("setOwned")}
        group["setsMissing"] = len(sets_missing)
        group["setsOwned"] = len(sets_owned)
        group["setsMissingNames"] = sorted(sets_missing)

    for s in prime_sets:
        missing = [p["label"] for p in s["parts"] if not p["count"]]
        s["haveCount"] = len(s["parts"]) - len(missing)
        s["total"] = len(s["parts"])
        s["missing"] = len(missing)
        s["missingLabels"] = missing
        s["relics"] = sorted(s.get("relics") or ())
        s["farmable"] = bool(s["relics"]) and not s["crafted"]
        s["status"] = "owned" if s["crafted"] else ("ready" if not missing else "missing")

    # 能做出来的排最前，其次是有遗物可刷且缺口小的，已拥有的沉底
    status_rank = {"ready": 0, "missing": 1, "owned": 2}
    prime_sets.sort(key=lambda s: (
        status_rank[s["status"]],
        0 if s["farmable"] else 1,
        s["missing"],
        s["zh"],
    ))

    # --- Mod：库存数量（RawUpgrades）与实例等级（Upgrades）是两个来源 ---
    raw_counts = {}
    for entry in inv.get("RawUpgrades", []) or []:
        item_type = entry.get("ItemType")
        if item_type:
            raw_counts[item_type] = raw_counts.get(item_type, 0) + int(entry.get("ItemCount") or 0)

    instances = {}
    for entry in inv.get("Upgrades", []) or []:
        item_type = entry.get("ItemType")
        if not item_type:
            continue
        level = None
        fingerprint = entry.get("UpgradeFingerprint")
        if isinstance(fingerprint, str):
            try:
                level = int(json.loads(fingerprint).get("lvl"))
            except (json.JSONDecodeError, TypeError, ValueError):
                level = None
        instances.setdefault(item_type, []).append(level)

    mod_types = set()
    for key in ("RawUpgrades",):
        for entry in inv.get(key, []) or []:
            if entry.get("ItemType"):
                mod_types.add(entry["ItemType"])
    mod_types |= {e.get("ItemType") for e in (inv.get("Upgrades") or []) if e.get("ItemType")}

    mods = []
    for item_type in mod_types:
        meta = mods_by_name.get(item_type) or {}
        levels = [lv for lv in instances.get(item_type, []) if lv is not None]
        mods.append({
            "zh": zh_of(lang, item_type) or meta.get("name") or short_name(item_type),
            "en": meta.get("name") or short_name(item_type),
            "count": raw_counts.get(item_type) or len(instances.get(item_type, [])) or 1,
            "rarity": meta.get("rarity"),
            "polarity": meta.get("polarity"),
            "maxLevel": meta.get("fusionLimit"),
            "topLevel": max(levels) if levels else None,
            "type": meta.get("type"),
        })
    mods.sort(key=lambda m: (-m["count"], m["zh"]))

    # --- 资源：只看 MiscItems，图纸和消耗品不属于这一栏 ---
    resources = []
    for entry in inv.get("MiscItems", []) or []:
        item_type = entry.get("ItemType")
        if not item_type or "/Projections/" in item_type:
            continue
        resources.append({
            "zh": zh_of(lang, item_type) or short_name(item_type),
            "en": short_name(item_type),
            "count": int(entry.get("ItemCount") or 0),
        })
    resources.sort(key=lambda r: -r["count"])

    # --- 星图 ---
    missions = []
    for entry in inv.get("Missions", []) or []:
        tag = entry.get("Tag")
        if not tag:
            continue
        info = nodes_by_tag.get(tag) or {}
        label = info.get("name")
        planet = info.get("planet")
        if not label:
            # solNodes 的值形如 "E Prime (Earth)"，星球在括号里
            raw = info.get("label") or ""
            if raw.endswith(")") and "(" in raw:
                head, _, tail = raw.rpartition("(")
                label = head.strip()
                planet = planet or tail.rstrip(")")
            elif raw:
                label = raw
        missions.append({
            "tag": tag,
            "name": label or tag,
            "planet": planet or ("仲裁" if tag.startswith("ClanNode") else "其他"),
            "type": info.get("type"),
            "completes": entry.get("Completes", 0),
        })

    state = {
        "mastery_rank": inv.get("PlayerLevel"),
        "credits": inv.get("RegularCredits"),
        "platinum": inv.get("PremiumCredits"),
        "endo": inv.get("FusionPoints"),
        "trades": inv.get("TradesRemaining"),
        "created": _extract_ms(inv.get("Created")),
        "synced": _oid_ms(inv.get("LastInventorySync")),
    }

    cats = {}
    for key in GEAR_KEYS:
        rows = [g for g in gear if g["cat"] == key]
        if rows:
            cats[key] = len(rows)

    return {
        "state": state,
        "cats": [{"key": k, "zh": GEAR_ZH.get(k, k), "count": v} for k, v in cats.items()],
        "relics": relics,
        "sets": prime_sets,
        "gear": gear,
        "mods": mods,
        "resources": resources,
        "missions": missions,
        "counts": {
            "relics": sum(r["total"] for r in relics),
            "relicKinds": len(relics),
            "mods": len(mods),
            "modStacks": sum(m["count"] for m in mods),
            "gear": len(gear),
            "resources": len(resources),
            "missions": len(missions),
            "primeSets": len(prime_sets),
            "setsOwned": sum(1 for s in prime_sets if s["status"] == "owned"),
            "setsReady": sum(1 for s in prime_sets if s["status"] == "ready"),
            "setPartsOwned": sum(s["haveCount"] for s in prime_sets),
            "setPartsTotal": sum(s["total"] for s in prime_sets),
        },
    }


def _extract_ms(node):
    if isinstance(node, dict):
        value = node.get("$date")
        if isinstance(value, dict) and value.get("$numberLong") is not None:
            return int(value["$numberLong"])
        if isinstance(value, (int, float)):
            return int(value)
    return None


def _oid_ms(node):
    if isinstance(node, dict):
        oid = node.get("$oid")
        if isinstance(oid, str) and len(oid) >= 8:
            try:
                return int(oid[:8], 16) * 1000
            except ValueError:
                return None
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description="生成背包数据浏览器")
    parser.add_argument("--snapshot", default=SNAPSHOT)
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--json-only", action="store_true")
    args = parser.parse_args(argv)

    data = build(args.snapshot)
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))

    if args.json_only:
        path = os.path.splitext(args.out)[0] + ".json"
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(payload)
        print(f"{path}  {len(payload)/1024:.0f} KB")
        print(json.dumps(data["counts"], ensure_ascii=False, indent=2))
        return 0

    template_path = os.path.join(ROOT, "scripts", "inventory_view_template.html")
    with open(template_path, encoding="utf-8") as fh:
        template = fh.read()
    html = template.replace("/*__DATA__*/", payload)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(html)

    # view.json 是 build_app_inventory.py 的输入。以前只有 --json-only 才写它，
    # 而编排里不带这个参数——于是 HTML 每次刷新、App 那份快照却一直在读三天前
    # 的旧文件，builtAt 却按当前时间重打，看起来「更新了」其实内容没动。
    json_path = os.path.splitext(args.out)[0] + ".json"
    with open(json_path, "w", encoding="utf-8") as fh:
        fh.write(payload)

    print(f"{args.out}  {len(html)/1024:.0f} KB")
    print(f"{json_path}  {len(payload)/1024:.0f} KB")
    print(json.dumps(data["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
