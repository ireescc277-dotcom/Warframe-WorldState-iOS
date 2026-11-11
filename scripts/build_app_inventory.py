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

import gzip
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW = os.path.join(ROOT, "data", "inventory", "view.json")
SNAPSHOT = os.path.join(ROOT, "data", "inventory", "latest.json.gz")
MARKET_ITEMS = os.path.join(ROOT, "data", "market", "items.json")
MARKET_PRICES = os.path.join(ROOT, "data", "market", "prices.json")
ICONS = os.path.join(ROOT, "data", "market", "icons.json")
OUT = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.json")
CACHE = os.path.join(ROOT, "data", "inventory", "aya_cache.json")

ALECA = os.path.expandvars(r"%LOCALAPPDATA%\AlecaFrame\cachedData\json")
WS_URL = "https://api.warframestat.us/pc?language=zh"

# 精炼档的短键，顺序固定：完整 / 优良 / 无瑕 / 光辉
REFINE = [("Intact", "I"), ("Exceptional", "E"), ("Flawless", "F"), ("Radiant", "R")]
REFINE_ZH = {"Intact": "完整", "Exceptional": "优良", "Flawless": "无瑕", "Radiant": "光辉"}
ERA_ZH = {"Lith": "古纪", "Meso": "前纪", "Neo": "中纪", "Axi": "后纪", "Requiem": "安魂"}


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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


def fetch_aya() -> dict:
    """当期 Varzia 的 Aya 遗物。拿不到就用上次缓存，不阻断构建。"""
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
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
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


def build() -> dict:
    view = load_json(VIEW)
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
    total_loose = 0
    total_ducats = 0
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
            # 已制成的套装，全部散件都能卖；未制成的要留一件
            sellable = count if s["status"] == "owned" else max(count - 1, 0)
            loose += sellable * unit
            loose_ducats += sellable * duc(p["id"])
            parts.append({
                "l": p["label"],
                "n": count,
                "p": unit,
                "d": duc(p["id"]),
            })
        total_loose += loose
        total_ducats += loose_ducats
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
    aya_doc = fetch_aya()
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
    profile = {}
    snap = os.path.join(ROOT, "data", "inventory", "latest.json.gz")
    if os.path.exists(snap):
        try:
            inv = json.loads(gzip.open(snap).read())
            # LastInventorySync 是 MongoDB ObjectId，前 4 字节就是同步时刻的
            # Unix 时间戳；它不是字符串，直接当字符串用会拿到 None。
            sync_raw = inv.get("LastInventorySync")
            sync_iso = None
            if isinstance(sync_raw, dict):
                oid = sync_raw.get("$oid")
                if isinstance(oid, str) and len(oid) >= 8:
                    try:
                        sync_iso = datetime.fromtimestamp(
                            int(oid[:8], 16), timezone.utc
                        ).strftime("%Y-%m-%dT%H:%M:%SZ")
                    except ValueError:
                        sync_iso = None
            elif isinstance(sync_raw, str):
                sync_iso = sync_raw
            profile = {
                "mr": int(inv.get("PlayerLevel") or 0),
                "plat": int(inv.get("PremiumCreditsFree") or 0) + int(inv.get("PremiumCredits") or 0),
                "credits": int(inv.get("RegularCredits") or 0),
                "sync": sync_iso,
            }
        except Exception:                                       # noqa: BLE001
            pass

    counts = view["counts"]
    return {
        "builtAt": now_iso(),
        "marketAt": load_json(MARKET_PRICES).get("ts"),
        "profile": profile,
        "totals": {
            "setsOwned": sum(1 for s in sets if s["status"] == "owned"),
            "setsReady": sum(1 for s in sets if s["status"] == "ready"),
            "setsClose": sum(1 for s in sets if s["status"] == "missing" and s["loose"] == 0
                             and s["total"] - s["have"] <= 2),
            "setsAll": len(sets),
            "loosePlat": total_loose,
            "looseDucats": total_ducats,
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


def main() -> int:
    if not os.path.exists(MARKET_PRICES):
        print("没有价格快照，先跑 `wf_market.py sync`", file=sys.stderr)
        return 1

    # builtAt 打的是「现在几点」，不是「数据是哪一刻的」。所以链路里只要有一步没产出
    # 新文件，结果就是时间戳一路更新、内容一直是几天前那份，从界面上根本看不出来。
    # 这里直接拿 view.json 和背包快照比时间，旧了就停下，别把陈货当新货推上去。
    if os.path.exists(SNAPSHOT) and os.path.exists(VIEW):
        if os.path.getmtime(VIEW) + 60 < os.path.getmtime(SNAPSHOT):
            print(
                "view.json 比背包快照旧：build_inventory_view.py 没有重跑？"
                f"\n  view.json   {datetime.fromtimestamp(os.path.getmtime(VIEW)):%Y-%m-%d %H:%M:%S}"
                f"\n  快照        {datetime.fromtimestamp(os.path.getmtime(SNAPSHOT)):%Y-%m-%d %H:%M:%S}",
                file=sys.stderr,
            )
            return 1

    data = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)

    t = data["totals"]
    print(f"套装 {t['setsAll']}（已制成 {t['setsOwned']} / 可制造 {t['setsReady']}）")
    print(f"散件可变现 {t['loosePlat']} p · {t['looseDucats']} Ducats")
    print(f"遗物 {t['relicKinds']} 代号 {t['relicUnits']} 个 · Aya {len(data['aya']['items'])} 项")
    print(f"-> {OUT}  {size//1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
