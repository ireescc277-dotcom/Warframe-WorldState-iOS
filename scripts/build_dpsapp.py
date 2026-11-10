"""把 DE 导出 + 本机配卡 + 敌人库打包成一台本地网页能直接吃的数据文件。

产物：data/dpsapp/data.js  (window.WF = {...})
不依赖服务器：用 <script> 引入，file:// 也能跑。
"""
from __future__ import annotations

import gzip
import json
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GD = os.path.join(ROOT, "data", "gamedata")
RAW = os.path.join(GD, "raw")
OUT = os.path.join(ROOT, "web", "dps")

# 伤害类型顺序：DE damagePerShot 的 20 个槽
DTYPES = [
    "impact", "puncture", "slash",
    "heat", "cold", "electricity", "toxin",
    "blast", "radiation", "magnetic", "viral", "corrosive", "gas",
]
PHYS = {"impact", "puncture", "slash"}
ELEM = {"heat", "cold", "electricity", "toxin"}
COMBO = {"blast", "radiation", "magnetic", "viral", "corrosive", "gas"}

# 文案 → 字段。只收影响直伤的，别的全部忽略。
STAT_MAP = {
    "damage": "dmg",
    "melee damage": "dmg",
    "base damage": "dmg",
    "critical chance": "cc",
    "critical damage": "cd",
    "multishot": "ms",
    "fire rate": "fr",
    "attack speed": "fr",
    "status chance": "sc",
    "status duration": "sdur",
    "status damage": "sdm",
    "magazine capacity": "mag",
    "reload speed": "rl",
    "punch through": "pt",
    "projectile speed": "pspd",
    "zoom": "zoom",
    "damage to grineer": "d_grineer",
    "damage to corpus": "d_corpus",
    "damage to infested": "d_infested",
    "damage to corrupted": "d_corrupted",
    "damage to narmer": "d_narmer",
    "damage to murmur": "d_murmur",
    "damage to sentient": "d_sentient",
}
for e in ("heat", "cold", "electricity", "toxin", "slash", "puncture", "impact",
          "blast", "radiation", "magnetic", "viral", "corrosive", "gas"):
    STAT_MAP[e] = e

STAT_RE = re.compile(r"^([+-]?\d+(?:\.\d+)?)\s*(%?)\s*(.+?)$")
TAG_RE = re.compile(r"<[^>]+>")


def parse_stats(lines):
    """['+165% Damage', '+90% <DT_FREEZE_COLOR>Cold'] -> {'dmg':165,'cold':90}"""
    out = {}
    for raw in lines or []:
        s = TAG_RE.sub("", raw).strip()
        m = STAT_RE.match(s)
        if not m:
            continue
        val = float(m.group(1))
        name = m.group(3).strip().lower()
        key = STAT_MAP.get(name)
        if not key:
            continue
        out[key] = out.get(key, 0.0) + val
    return out


# ---------------------------------------------------------------- 敌人类型
# DE 的敌人导出只有 血量/护甲/护盾 三个数值，没有类型。
# 这张表按阵营 + 名字规则归类，conf 标出可信度。
FACTION_DEFAULT = {
    "Grineer":        ("Cloned Flesh", "Ferrite", "none", "high"),
    "Kuva Grineer":   ("Cloned Flesh", "Ferrite", "none", "high"),
    "Corpus":         ("Flesh", "none", "Shield", "high"),
    "Corpus Amalgam": ("Flesh", "none", "Shield", "high"),
    "Infested":       ("Infested", "none", "none", "high"),
    "Infested Deimos": ("Infested Flesh", "none", "none", "low"),
    "Orokin":         ("Cloned Flesh", "Ferrite", "none", "low"),
    "Sentient":       ("Robotic", "Ferrite", "none", "low"),
    "Narmer":         ("Flesh", "none", "Shield", "low"),
    "Murmur":         ("Robotic", "none", "none", "low"),
    "Stalker":        ("Flesh", "none", "none", "low"),
    "Neutral":        ("Flesh", "none", "none", "low"),
    "Anarchs":        ("Flesh", "none", "Shield", "low"),
    "Scaldra":        ("Flesh", "Ferrite", "none", "low"),
    "Techrot":        ("Infested Flesh", "none", "none", "low"),
    "Zariman":        ("Flesh", "none", "none", "low"),
}

# 名字命中就改判（先命中先用）
NAME_RULES = [
    # Grineer / Kuva：合金甲单位
    (re.compile(r"bombard|napalm|elite lancer|eviscerator|guardsman|prosecutor|kela|vay hek", re.I),
     ("Cloned Flesh", "Alloy", "none", "high")),
    # 感染体：远古 / 孵化者 是化石化
    (re.compile(r"ancient|boiler|brood mother|jugulus|saxum|carnis|lephantis", re.I),
     ("Fossilized", "none", "none", "high")),
    # 感染体：共生体 / 焦油 属于感染血肉
    (re.compile(r"mutalist|tar mutalist|swarm|osprey", re.I),
     ("Infested Flesh", "none", "none", "low")),
    # 科普斯：原型护盾
    (re.compile(r"\btech\b|sniper crewman|detron crewman|corpus target|hyena|razorback", re.I),
     ("Flesh", "none", "Proto Shield", "low")),
    # Orokin / 堕落者：按兵种拆
    (re.compile(r"corrupted bombard|corrupted napalm", re.I),
     ("Cloned Flesh", "Alloy", "none", "high")),
    (re.compile(r"corrupted lancer|corrupted heavy gunner|corrupted butcher|corrupted gunner", re.I),
     ("Cloned Flesh", "Ferrite", "none", "high")),
    (re.compile(r"corrupted crewman|corrupted moa|corrupted drone|corrupted nullifier", re.I),
     ("Flesh", "none", "Shield", "high")),
    (re.compile(r"corrupted ancient", re.I),
     ("Fossilized", "none", "none", "high")),
]


def resolve_types(name, faction):
    for rx, triple in NAME_RULES:
        if rx.search(name):
            return triple
    return FACTION_DEFAULT.get(faction, ("Flesh", "none", "none", "low"))


def load_enemies():
    path = os.path.join(GD, "ref", "enemies-min.json")
    rows = json.load(open(path, encoding="utf-8"))
    out = []
    for r in rows:
        name = r["name"]
        fac = r.get("faction") or "Neutral"
        ht, at, st, conf = resolve_types(name, fac)
        e = {
            "n": name,
            "f": fac,
            "hp": float((r.get("health") or {}).get("val") or 0),
            "ar": float((r.get("armor") or {}).get("val") or 0),
            "sh": float((r.get("shield") or {}).get("val") or 0),
            "ht": ht, "at": at, "st": st,
            "cf": conf,
        }
        if r.get("overguard"):
            e["og"] = float(str(r["overguard"].get("val") if isinstance(r.get("overguard"), dict) else r["overguard"]).strip() or 0) or None
        if r.get("immun"):
            e["im"] = r["immun"]
        if r.get("innateDR"):
            e["dr"] = r["innateDR"]
        out.append({k: v for k, v in e.items() if v is not None})
    out.sort(key=lambda x: (x["f"], x["n"]))
    return out


def load_weapons():
    g = json.load(open(os.path.join(GD, "gamedata.json"), encoding="utf-8"))
    return g["weapons"]


def load_mods():
    g = json.load(open(os.path.join(GD, "gamedata.json"), encoding="utf-8"))
    mods = {}
    for uid, m in g["mods"].items():
        levels = [parse_stats(lv) for lv in (m.get("lv") or [])]
        if not levels:
            continue
        mods[uid] = {
            "n": m["n"], "z": m.get("z") or m["n"],
            "mx": m.get("mx") or 0,
            "t": m.get("t") or "",
            "pol": m.get("pol") or "",
            "d": m.get("d") or 0,
            "lv": levels,
        }
    return mods


def load_builds(weapons):
    path = os.path.join(ROOT, "data", "inventory", "latest.json.gz")
    d = json.load(gzip.open(path, "rt", encoding="utf-8"))
    inst = {}
    for u in d.get("Upgrades") or []:
        try:
            iid = u["ItemId"]["$oid"]
        except Exception:
            continue
        fp = u.get("UpgradeFingerprint")
        lvl = 0
        if fp:
            try:
                lvl = int(json.loads(fp).get("lvl") or 0)
            except Exception:
                lvl = 0
        inst[iid] = (u.get("ItemType"), lvl)

    builds = []
    for cat in ("LongGuns", "Pistols", "Melee", "SentinelWeapons", "SpaceGuns", "SpaceMelee"):
        for w in d.get(cat) or []:
            if not isinstance(w, dict):
                continue
            uid = w.get("ItemType")
            if uid not in weapons:
                continue
            configs = []
            for cfg in w.get("Configs") or []:
                if not isinstance(cfg, dict):
                    continue
                slots = []
                for s in cfg.get("Upgrades") or []:
                    if not s:
                        slots.append(None)
                        continue
                    if s.startswith("/"):
                        slots.append({"m": s, "lv": 0})
                        continue
                    hit = inst.get(s)
                    slots.append({"m": hit[0], "lv": hit[1]} if hit else None)
                if any(slots):
                    configs.append(slots)
            if configs:
                builds.append({"w": uid, "slots": configs})
    return builds


def main():
    os.makedirs(OUT, exist_ok=True)
    weapons = load_weapons()
    mods = load_mods()
    builds = load_builds(weapons)
    enemies = load_enemies()

    # 只留有配卡的武器，外加全部 mod（供选卡器用）
    payload = {
        "meta": {
            "builtAt": time.strftime("%Y-%m-%d %H:%M:%S"),
            "weapons": len(weapons),
            "mods": len(mods),
            "builds": len(builds),
            "enemies": len(enemies),
        },
        "w": weapons,
        "m": mods,
        "b": builds,
        "e": enemies,
    }
    # 精简：武器只保留需要的字段
    slim = {}
    for uid, w in weapons.items():
        slim[uid] = {k: w[k] for k in ("n", "z", "dmg", "td", "cc", "cm", "sc", "fr",
                                       "mag", "rl", "ms", "tr", "cat", "mr") if k in w}
    payload["w"] = slim

    js = "window.WF=" + json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + ";\n"
    with open(os.path.join(OUT, "data.js"), "w", encoding="utf-8") as f:
        f.write(js)
    print(f"data.js {len(js)/1024:.0f} KB | 武器 {len(slim)} | mod {len(mods)} | 配卡 {len(builds)} | 敌人 {len(enemies)}")

    # 自包含单文件版：把 data.js 内联进 index.html
    index = os.path.join(OUT, "index.html")
    if os.path.exists(index):
        html = open(index, encoding="utf-8").read()
        if '<script src="data.js"></script>' in html:
            html = html.replace('<script src="data.js"></script>', "<script>\n" + js + "</script>")
            with open(os.path.join(OUT, "dps-standalone.html"), "w", encoding="utf-8") as f:
                f.write(html)
            print(f"dps-standalone.html {(len(html))/1024:.0f} KB（单文件，双击即可打开）")

    # 覆盖率自检：配卡里出现但没解析出数值的 mod
    missing = {}
    for b in builds:
        for cfg in b["slots"]:
            for s in cfg:
                if not s:
                    continue
                m = mods.get(s["m"])
                if not m:
                    missing[s["m"]] = missing.get(s["m"], 0) + 1
    if missing:
        print(f"未解析 mod {len(missing)} 个（路径型/未收录）")
        for k, v in list(missing.items())[:8]:
            print("   ", k.split("/")[-1], v)


if __name__ == "__main__":
    main()
