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


# ---------------------------------------------------------------- 敌人
# Update 36（2024-06）之后，血量/护甲/护盾类型已合并，克制改挂在阵营上：
# 弱点 ×1.5、抗性 ×0.5，按伤害类型查。所以这里只需要阵营键，不需要类型表。
FACTION_KEY = {
    "grineer": "Grineer",
    "kuva grineer": "Kuva Grineer",
    "corpus": "Corpus",
    "corpus amalgam": "Corpus Amalgam",
    "infested": "Infested",
    "infestation": "Infested",
    "infested deimos": "Infested Deimos",
    "deimos infested": "Infested Deimos",
    "orokin": "Orokin",
    "sentient": "Sentient",
    "narmer": "Narmer",
    "murmur": "Murmur",
    "scaldra": "Scaldra",
    "techrot": "Techrot",
    "zariman": "Zariman",
}


def faction_key(raw: str) -> str:
    return FACTION_KEY.get((raw or "").strip().lower(), "")


def load_enemies():
    path = os.path.join(GD, "ref", "enemies-min.json")
    rows = json.load(open(path, encoding="utf-8"))
    out = []
    for r in rows:
        name = (r.get("name") or "").strip()
        fac = (r.get("faction") or "").strip() or "Neutral"
        e = {
            "n": name,
            "f": fac,
            "fk": faction_key(fac),
            "hp": float((r.get("health") or {}).get("val") or 0),
            "ar": float((r.get("armor") or {}).get("val") or 0),
            "sh": float((r.get("shield") or {}).get("val") or 0),
        }
        if r.get("b_lvl"):
            e["bl"] = int(r["b_lvl"])
        if r.get("overguard"):
            og = r["overguard"].get("val") if isinstance(r.get("overguard"), dict) else r["overguard"]
            v = float(str(og).strip() or 0)
            if v:
                e["og"] = v
        if r.get("immun"):
            e["im"] = r["immun"]
        if r.get("innateDR"):
            e["dr"] = r["innateDR"]
        if r.get("eximusOff"):
            e["xo"] = 1
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
                b = {"w": uid, "slots": configs}
                if w.get("SkillTree"):
                    b["sk"] = w["SkillTree"]      # 灵化进化：每一位 = 那一层选的 slot
                builds.append(b)
    return builds


# ---------------------------------------------------------------- 灵化
# Genesis 数据按基础型号记录（boar_incarnon 同时对应 Boar 和 Boar Prime），
# 所以先把变体词摘掉再查表。
INC_VARIANTS = {"prime", "prisma", "vandal", "wraith", "kuva", "tenet", "dex",
                "mk1", "sancti", "rakta", "telos", "vaykor", "synoid", "secura",
                "carmine", "brutalist"}


def inc_slug(name: str) -> str:
    s = (name or "").lower()
    s = re.sub(r"[&'.,()!:']", " ", s).replace("-", " ")
    return "_".join(w for w in s.split() if w and w not in INC_VARIANTS)


def inc_full_slug(name: str) -> str:
    """保留变体词的写法，用来查 variantStatChanges（paris_prime / prisma_skana）。"""
    s = (name or "").lower()
    s = re.sub(r"[&'.,()!:']", " ", s).replace("-", " ")
    return "_".join(w for w in s.split() if w)


def load_incarnon(weapons):
    """uniqueName -> {id, ev:[{t,s,n,d,c}]}，只收能对上的。

    进化数值按型号分叉：variantStatChanges 里有本型号就用它，
    否则退回 statChanges（Boar / Torid 这类没有分叉的走这条）。
    """
    path = os.path.join(GD, "incarnon.json")
    if not os.path.exists(path):
        return {}
    data = json.load(open(path, encoding="utf-8"))
    out = {}
    for uid, w in weapons.items():
        nm = w.get("n") or ""
        sl, full = inc_slug(nm), inc_full_slug(nm)
        for cand in (sl, sl + "_incarnon"):
            if cand not in data:
                continue
            ev = []
            for e in data[cand]:
                c = e.get("statChanges") or {}
                vt = e.get("variantStatChanges") or {}
                if full in vt:
                    c = vt[full]
                elif sl in vt:
                    c = vt[sl]
                ev.append({
                    "t": e["tier"], "s": e["slot"], "n": e["name"],
                    "d": (e.get("description") or "").replace("\n", " ")[:220],
                    "c": c,
                })
            out[uid] = {"id": cand, "ev": ev}
            break
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    weapons = load_weapons()
    mods = load_mods()
    builds = load_builds(weapons)
    enemies = load_enemies()
    incarnon = load_incarnon(weapons)

    # 只留有配卡的武器，外加全部 mod（供选卡器用）
    payload = {
        "meta": {
            "builtAt": time.strftime("%Y-%m-%d %H:%M:%S"),
            "weapons": len(weapons),
            "mods": len(mods),
            "builds": len(builds),
            "enemies": len(enemies),
            "incarnon": len(incarnon),
        },
        "w": weapons,
        "m": mods,
        "b": builds,
        "e": enemies,
        "i": incarnon,
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

    # 灵化：有 SkillTree 但没对上进化表的，逐条报出来
    withst = [b for b in builds if b.get("sk")]
    nomap = [b for b in withst if b["w"] not in incarnon]
    print(f"灵化：{len(withst)} 把带 SkillTree，{len(withst)-len(nomap)} 把已匹配进化表")
    for b in nomap[:6]:
        print("   未匹配：", weapons[b["w"]].get("n"), b["sk"])


if __name__ == "__main__":
    main()
