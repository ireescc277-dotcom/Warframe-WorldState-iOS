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
                    if hit and "Randomized" in (hit[0] or ""):
                        # 紫卡：ItemType 是模板名，真正的数值在指纹里
                        slots.append({"m": "RIVEN:" + s, "lv": 0})
                    else:
                        slots.append({"m": hit[0], "lv": hit[1]} if hit else None)
                if any(slots):
                    configs.append(slots)
            if configs:
                b = {"w": uid, "slots": configs}
                # 灵化进化节点选择：每一位是那一层选中的 slot 号，
                # 长度等于已解锁层数，和 EvolutionProgress.Rank 一致。
                tree = w.get("SkillTree")
                if tree:
                    b["tree"] = tree
                builds.append(b)
    return builds


# ---------------------------------------------------------------- 灵化
def slug(name: str) -> str:
    """'Boar Prime' -> boar_prime，'Ack & Brunt' -> ack_&_brunt"""
    s = (name or "").lower().strip()
    s = re.sub(r"[^a-z0-9&\s-]", "", s)
    s = re.sub(r"[\s-]+", "_", s)
    return s.strip("_")


def load_incarnon(weapons, builds):
    """灵化数据：形态数值 + 每层进化节点。

    数值来自 Voidforge 的 wiki 解析版（incarnon_wiki.json），骨架和形态来自
    incarnon.json。内联的 statChanges 基本是空的，以 wiki 版为准。
    """
    p1 = os.path.join(GD, "ref", "incarnon.json")
    p2 = os.path.join(GD, "ref", "incarnon_wiki.json")
    if not (os.path.exists(p1) and os.path.exists(p2)):
        return {}
    skel = {x["weaponId"]: x for x in json.load(open(p1, encoding="utf-8"))}
    wiki = json.load(open(p2, encoding="utf-8"))

    var2id = {}
    for wid, x in skel.items():
        for v in x.get("variants") or []:
            var2id[v] = wid

    have_tree = {b["w"]: b.get("tree") for b in builds if b.get("tree")}
    out = {}
    for uid, tree in have_tree.items():
        w = weapons.get(uid) or {}
        s = slug(w.get("n"))
        wid = var2id.get(s) or (s if s in skel else None)
        if not wid or wid not in skel:
            continue
        sk = skel[wid]
        nodes = wiki.get(wid) or sk.get("evolutions") or []

        # 按 SkillTree 解析出实际选中的节点
        picked = []
        for i, ch in enumerate(tree):
            tier = i + 1
            try:
                slot = int(ch)
            except ValueError:
                continue
            hit = [n for n in nodes if n.get("tier") == tier and n.get("slot") == slot]
            if not hit:
                continue
            n = hit[0]
            picked.append({
                "t": tier, "s": slot, "n": n.get("name") or "",
                "d": n.get("description") or "",
                "sc": n.get("statChanges") or {},
            })

        forms = []
        for f in sk.get("forms") or []:
            dmg = {}
            for k in DTYPES:
                if f.get(k):
                    dmg[k] = f[k]
            forms.append({
                "n": f.get("name") or "",
                "td": f.get("damage") or 0,
                "cc": f.get("criticalChance") or 0,
                "cm": f.get("criticalMultiplier") or 1,
                "sc": f.get("statusChance") or 0,
                "fr": f.get("fireRate") or 0,
                "mag": f.get("magazine"),
                "rl": f.get("reloadTime"),
                "ms": f.get("multishot"),
                "dmg": dmg,
                "tr": f.get("triggerType") or "",
                "dt": f.get("damageType") or "",
            })
        if len(forms) < 2:
            continue
        out[uid] = {
            "id": wid, "name": sk.get("weaponName") or "", "tree": tree,
            "forms": forms, "picked": picked,
            "all": [{"t": n.get("tier"), "s": n.get("slot"), "n": n.get("name") or ""}
                    for n in nodes],
        }
    return out


# ---------------------------------------------------------------- 紫卡
# 公式来自 calamity-inc/warframe-riven-info 的 RivenParser.js：
#   attenuation = 1.5(SPECIFIC_FIT) * disposition * 10(RIVEN_BASE_DRAIN)
#   buff  = tagBase * attenuation * 1.25^curses * lerp(0.9,1.1, Value/0x3FFFFFFF)
#           * numBuffsAtten[词条数] * (lvl+1)
# Value 是 0..0x3FFFFFFF 的整数，不是百分比。
RIVEN_BUFF_ATTEN = [0, 1, 0.66000003, 0.5, 0.40000001, 0.34999999]
RIVEN_CURSE_ATTEN = [0, 1, 0.33000001, 0.5, 1.25, 1.5]
RIVEN_MAX = 0x3FFFFFFF

RIVEN_LBL = {
    "WeaponCritDamageMod": "暴击伤害", "WeaponCritChanceMod": "暴击率",
    "WeaponDamageAmountMod": "伤害", "WeaponMeleeDamageMod": "近战伤害",
    "WeaponFireRateMod": "射速", "WeaponFireIterationsMod": "多重弹",
    "WeaponProcTimeMod": "触发时间", "WeaponStunChanceMod": "触发几率",
    "WeaponReloadSpeedMod": "装填速度", "WeaponClipMaxMod": "弹匣容量",
    "WeaponAmmoMaxMod": "弹药上限", "WeaponAmmoEfficiency": "弹药效率",
    "WeaponZoomFovMod": "缩放", "WeaponRecoilReductionMod": "后坐力",
    "WeaponProjectileSpeedMod": "弹丸速度", "WeaponPunctureDepthMod": "穿透",
    "WeaponArmorPiercingDamageMod": "穿刺伤害",
    "WeaponImpactDamageMod": "冲击伤害", "WeaponSlashDamageMod": "切割伤害",
    "WeaponHeatDamageMod": "火焰伤害", "WeaponFireDamageMod": "火焰伤害",
    "WeaponFreezeDamageMod": "冰冻伤害", "WeaponColdDamageMod": "冰冻伤害",
    "WeaponElectricityDamageMod": "电击伤害", "WeaponToxinDamageMod": "毒素伤害",
    "WeaponPoisonDamageMod": "毒素伤害", "WeaponGasDamageMod": "毒气伤害",
    "WeaponCorrosiveDamageMod": "腐蚀伤害", "WeaponMagneticDamageMod": "磁力伤害",
    "WeaponRadiationDamageMod": "辐射伤害", "WeaponViralDamageMod": "病毒伤害",
    "WeaponFactionDamageGrineer": "对 Grineer 伤害",
    "WeaponFactionDamageCorpus": "对 Corpus 伤害",
    "WeaponFactionDamageInfested": "对 Infested 伤害",
    "WeaponFactionDamageCorrupted": "对 Orokin 伤害",
    "WeaponMeleeFactionDamageGrineer": "对 Grineer 近战伤害",
    "WeaponMeleeFactionDamageCorpus": "对 Corpus 近战伤害",
    "WeaponMeleeFactionDamageInfested": "对 Infested 近战伤害",
    "WeaponMeleeRangeIncMod": "近战范围",
    "WeaponMeleeFinisherDamageMod": "处决伤害",
    "WeaponMeleeComboEfficiencyMod": "连击效率",
    "WeaponMeleeComboBonusOnHitMod": "命中连击",
    "WeaponMeleeComboInitialBonusMod": "初始连击",
    "ComboDurationMod": "连击持续时间",
    "SlideAttackCritChanceMod": "滑砍暴击率",
}


# 这几个词条的单位是绝对值（连击数、秒、米），不是百分比。
# RivenParser 的 valueToDisplayValue 对它们单独 ×10 处理。
RIVEN_ABS_TAGS = {"WeaponMeleeComboInitialBonusMod", "ComboDurationMod", "WeaponMeleeRangeIncMod"}
# 紫卡词条 Tag → 计算器内部字段（值是百分数，和普通 mod 一致）
RIVEN_FIELD = {
    "WeaponCritChanceMod": "cc", "WeaponCritDamageMod": "cd",
    "WeaponDamageAmountMod": "dmg", "WeaponMeleeDamageMod": "dmg",
    "WeaponFireRateMod": "fr", "WeaponFireIterationsMod": "ms",
    "WeaponProcTimeMod": "sdur", "WeaponStunChanceMod": "sc",
    "WeaponReloadSpeedMod": "rl", "WeaponClipMaxMod": "mag",
    "WeaponFireDamageMod": "heat", "WeaponHeatDamageMod": "heat",
    "WeaponFreezeDamageMod": "cold", "WeaponColdDamageMod": "cold",
    "WeaponElectricityDamageMod": "electricity",
    "WeaponToxinDamageMod": "toxin", "WeaponPoisonDamageMod": "toxin",
    "WeaponImpactDamageMod": "impact", "WeaponSlashDamageMod": "slash",
    "WeaponPunctureDepthMod": "puncture", "WeaponArmorPiercingDamageMod": "puncture",
    "WeaponFactionDamageGrineer": "d_grineer", "WeaponFactionDamageCorpus": "d_corpus",
    "WeaponFactionDamageInfested": "d_infested",
    "WeaponFactionDamageCorrupted": "d_corrupted",
    "WeaponMeleeFactionDamageGrineer": "d_grineer",
    "WeaponMeleeFactionDamageCorpus": "d_corpus",
    "WeaponMeleeFactionDamageInfested": "d_infested",
}


def load_rivens(weapons):
    """背包里的紫卡。返回 (清单, {实例ID: 合成mod})。

    数值按 calamity-inc/warframe-riven-info 的 RivenParser 公式在本地算。
    """
    p = os.path.join(GD, "ref", "riven", "riven_tags.json")
    if not os.path.exists(p):
        return [], {}
    tags = json.load(open(p, encoding="utf-8"))
    path = os.path.join(ROOT, "data", "inventory", "latest.json.gz")
    d = json.load(gzip.open(path, "rt", encoding="utf-8"))

    out, as_mod = [], {}
    for u in d.get("Upgrades") or []:
        it = u.get("ItemType") or ""
        if "Randomized" not in it:
            continue
        rtype = it.split("/")[-1]
        base = tags.get(rtype)
        if not base:
            continue
        try:
            fp = json.loads(u.get("UpgradeFingerprint") or "{}")
        except Exception:
            continue
        bytag = {x["tag"]: x for x in base}
        compat = fp.get("compat") or ""
        disp = (weapons.get(compat) or {}).get("om") or 1.2
        atten = 1.5 * disp * 10
        curses = fp.get("curses") or []
        buffs = fp.get("buffs") or []
        curse_atten = 1.25 ** len(curses)
        lvl = int(fp.get("lvl") or 0)

        def one(tag, raw, is_curse):
            t = bytag.get(tag)
            if not t or not isinstance(raw, (int, float)):
                return None
            v = t["value"] * (-1.0 if is_curse else 1.0) * atten
            if not is_curse:
                v *= curse_atten
                v *= RIVEN_BUFF_ATTEN[min(len(buffs), 5)]
            else:
                v *= RIVEN_CURSE_ATTEN[min(len(buffs), 5)]
                v *= RIVEN_BUFF_ATTEN[min(len(curses), 5)]
            f = max(0.0, min(1.0, raw / RIVEN_MAX))
            v *= 0.9 + 0.2 * f
            v *= (lvl + 1)
            return round(v, 4)

        rows, fields = [], {}
        for b in buffs:
            tag = b.get("Tag")
            v = one(tag, b.get("Value"), False)
            rows.append({"t": tag, "n": RIVEN_LBL.get(tag, tag), "v": v,
                         "abs": 1 if tag in RIVEN_ABS_TAGS else 0})
            f = RIVEN_FIELD.get(tag)
            if f and v is not None:
                fields[f] = fields.get(f, 0) + v * 100
        for c in curses:
            tag = c.get("Tag")
            v = one(tag, c.get("Value"), True)
            rows.append({"t": tag, "n": RIVEN_LBL.get(tag, tag), "v": v, "c": 1,
                         "abs": 1 if tag in RIVEN_ABS_TAGS else 0})
            f = RIVEN_FIELD.get(tag)
            if f and v is not None:
                fields[f] = fields.get(f, 0) + v * 100

        # 按 RivenParser 的规则拼名字：value 最大的 prefix + 最小的 suffix
        sorted_b = sorted(buffs, key=lambda b: b.get("Value") or 0, reverse=True)
        name = ""
        for i, b in enumerate(sorted_b):
            t = bytag.get(b.get("Tag")) or {}
            if i == len(sorted_b) - 1:
                name += t.get("suffix") or ""
            elif i == 0:
                name += (t.get("prefix") or "").capitalize()
            else:
                name += "-" + (t.get("prefix") or "")
        name = name or "Riven"

        iid = (u.get("ItemId") or {}).get("$oid") or ""
        out.append({
            "id": iid, "compat": compat,
            "w": (weapons.get(compat) or {}).get("n") or
                 (compat.split("/")[-1] if compat else "未开卡"),
            "nm": name,
            "lvl": lvl, "rr": int(fp.get("rerolls") or 0),
            "pol": fp.get("pol") or "", "disp": disp,
            "s": rows,
        })
        if iid:
            as_mod["RIVEN:" + iid] = {
                "n": name, "z": name, "mx": 8, "t": "", "pol": fp.get("pol") or "",
                "d": 16, "lv": [fields], "rv": 1,
            }
    out.sort(key=lambda x: (x["w"], -x["lvl"]))
    return out, as_mod


def main():
    os.makedirs(OUT, exist_ok=True)
    weapons = load_weapons()
    mods = load_mods()
    rivens, riven_mods = load_rivens(weapons)
    mods.update(riven_mods)
    builds = load_builds(weapons)
    enemies = load_enemies()
    incarnon = load_incarnon(weapons, builds)

    # 只留有配卡的武器，外加全部 mod（供选卡器用）
    payload = {
        "meta": {
            "builtAt": time.strftime("%Y-%m-%d %H:%M:%S"),
            "weapons": len(weapons),
            "mods": len(mods),
            "builds": len(builds),
            "enemies": len(enemies),
            "incarnon": len(incarnon),
            "rivens": len(rivens),
        },
        "w": weapons,
        "m": mods,
        "b": builds,
        "e": enemies,
        "i": incarnon,
        "rv": rivens,
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
