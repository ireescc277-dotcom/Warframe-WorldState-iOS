#!/usr/bin/env python3
"""Rebuild per-node mission type / planet metadata inside DefaultDict.json.

Source of truth: WFCD warframe-worldstate-data `data/solNodes.json`.
The app needs, for every star-chart node:
  mt       mission type code (MT_*), used to build the exhaustive watch tree
  planet   Chinese planet name, used to group arbitration nodes by 星球

Usage:
  python scripts/build_node_catalog.py --source /path/to/solNodes.json
  python scripts/build_node_catalog.py --fetch
"""

import argparse
import json
import os
import re
import sys
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICT_PATH = os.path.join(ROOT, "WarframeWatch", "Resources", "DefaultDict.json")
SOURCE_URL = "https://raw.githubusercontent.com/WFCD/warframe-worldstate-data/master/data/solNodes.json"

# Mission type codes follow DE's own MT_* enum as published in WFCD
# warframe-worldstate-data / data/missionTypes.json. Two Zariman-era modes have
# no DE code of their own, so they get a synthetic code here — it only has to be
# stable and unique, because `mt` is what the watch tree groups nodes by.
TYPE_MAP = {
    "Capture": "MT_CAPTURE",
    "Extermination": "MT_EXTERMINATION",
    "Survival": "MT_SURVIVAL",
    "Dark Sector Survival": "MT_SURVIVAL",
    "Defense": "MT_DEFENSE",
    "Dark Sector Defense": "MT_DEFENSE",
    "Mobile Defense": "MT_MOBILE_DEFENSE",
    "Sabotage": "MT_SABOTAGE",
    "Orokin Sabotage": "MT_SABOTAGE",
    "Rescue": "MT_RESCUE",
    "Spy": "MT_INTEL",
    "Interception": "MT_TERRITORY",
    "Disruption": "MT_ARTIFACT",
    "Dark Sector Disruption": "MT_ARTIFACT",
    "Excavation": "MT_EXCAVATE",
    "Dark Sector Excavation": "MT_EXCAVATE",
    "Assassination": "MT_ASSASSINATION",
    "Arena": "MT_ARENA",
    "Free Roam": "MT_LANDSCAPE",
    "Skirmish": "MT_SKIRMISH",
    "Hijack": "MT_RETRIEVAL",
    "Assault": "MT_ASSAULT",
    "Hive": "MT_HIVE",
    "Hive Sabotage": "MT_HIVE",
    "Defection": "MT_EVACUATION",
    "Dark Sector Defection": "MT_EVACUATION",
    "Infested Salvage": "MT_PURIFY",
    "Void Flood": "MT_CORRUPTION",
    "Void Cascade": "MT_VOID_CASCADE",
    "Void Armageddon": "MT_VOID_ARMAGEDDON",
    "Alchemy": "MT_ALCHEMY",
    "Mirror Defense": "MT_MIRROR_DEFENSE",
    "Ascension": "MT_ASCENSION",
}

# Display names for codes that do not exist in the shipped missionTypes table.
EXTRA_MISSION_TYPE_NAMES = {
    "MT_VOID_ARMAGEDDON": "虚空决战",
    "MT_MIRROR_DEFENSE": "镜像防御",
    "MT_SKIRMISH": "前哨战",
}

PLANET_MAP = {
    "Mercury": "水星",
    "Venus": "金星",
    "Earth": "地球",
    "Mars": "火星",
    "Phobos": "火卫一",
    "Deimos": "火卫二",
    "Ceres": "谷神星",
    "Jupiter": "木星",
    "Europa": "欧罗巴",
    "Saturn": "土星",
    "Uranus": "天王星",
    "Neptune": "海王星",
    "Pluto": "冥王星",
    "Sedna": "赛德娜",
    "Eris": "阋神星",
    "Lua": "月球",
    "Void": "虚空",
    "Veil": "面纱比邻星域",
    "Kuva Fortress": "赤毒要塞",
    "Zariman": "扎里曼",
    "Duviri": "杜维里",
}


def load_source(path):
    if path:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    with urllib.request.urlopen(SOURCE_URL, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def split_planet(value):
    match = re.search(r"\(([^()]+)\)\s*$", value or "")
    if not match:
        return value, None
    return value[: match.start()].strip(), match.group(1).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", help="local solNodes.json path")
    parser.add_argument("--fetch", action="store_true", help="download from WFCD")
    args = parser.parse_args()

    source = load_source(None if args.fetch else args.source)

    with open(DICT_PATH, "r", encoding="utf-8") as fh:
        payload = json.load(fh)

    nodes = payload["nodes"]
    mission_types = payload.setdefault("missionTypes", {})
    mission_types.update(EXTRA_MISSION_TYPE_NAMES)
    typed = 0
    planeted = 0
    renamed = 0
    skipped = []

    for node_id, entry in nodes.items():
        raw = source.get(node_id)
        if not raw:
            skipped.append(node_id)
            continue

        mt = TYPE_MAP.get(raw.get("type"))
        _, planet_en = split_planet(raw.get("value", ""))
        planet = PLANET_MAP.get(planet_en) if planet_en else None

        if mt:
            entry["mt"] = mt
            typed += 1
        if planet:
            entry["planet"] = planet
            planeted += 1

        # A handful of nodes still carry the English mode name; the Chinese name
        # for the mode is authoritative once we know the code.
        label = mission_types.get(mt) if mt else None
        if label and not any("\u4e00" <= ch <= "\u9fff" for ch in entry.get("t", "")):
            entry["t"] = label
            renamed += 1

        # Only touch names whose planet suffix is still English.
        if planet and "n" in entry and not entry["n"].rstrip().endswith(f"（{planet}）"):
            base = re.sub(r"\s*[（(][^()（）]*[)）]\s*$", "", entry["n"]).strip()
            entry["n"] = f"{base}（{planet}）" if base else entry["n"]

    with open(DICT_PATH, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    print(f"nodes total      : {len(nodes)}")
    print(f"with mission type: {typed}")
    print(f"with planet      : {planeted}")
    print(f"mode names fixed : {renamed}")
    print(f"mission types    : {len(mission_types)}")
    print(f"unmapped ids     : {len(skipped)}")


if __name__ == "__main__":
    main()
