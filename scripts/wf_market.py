#!/usr/bin/env python3
"""warframe.market 价格抓取与聚合。

market 的 v1 接口在 2026-11 已全部返回 403 Deprecated，只有 v2 可用：

    GET /v2/items                    # 3893 项，含 gameRef（就是游戏里的 uniqueName）
    GET /v2/orders/item/{id}         # 单件全部订单，含卖家在线状态

`gameRef` 是这套东西能成立的关键：它和背包里的 ItemType 同源，不用靠名字猜。
套装一侧是 `/Lotus/Powersuits/Frost/FrostPrime`，部件一侧 market 用
`...ChassisBlueprint` 而套装字典用 `...ChassisComponent`，所以查价要带别名。

聚合口径（都取自卖家侧 sell 单）：
    sellOnline  在线/游戏中的卖家最低价 —— 这是真能立刻成交的价
    sellMin     全部卖家最低价 —— 挂单多但卖家可能几天不上线
    buyMax      最高收购价 —— 想立刻出手能拿到的价
    sellers     卖单数，流动性
    online      在线卖家数

用法：
    python scripts/wf_market.py items            # 拉商品目录（含 gameRef → slug）
    python scripts/wf_market.py sync             # 抓目标清单的价格
    python scripts/wf_market.py sync --limit 20  # 试抓
    python scripts/wf_market.py report           # 按当前背包算持仓价值
"""
from __future__ import annotations

import argparse
import concurrent.futures as futures
import gzip
import json
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKET_DIR = os.path.join(ROOT, "data", "market")
ITEMS_PATH = os.path.join(MARKET_DIR, "items.json")
PRICES_PATH = os.path.join(MARKET_DIR, "prices.json")
VIEW_PATH = os.path.join(ROOT, "data", "inventory", "view.json")
AYA_CACHE = os.path.join(ROOT, "data", "inventory", "aya_cache.json")

API = "https://api.warframe.market/v2"
UA = "WarframeWatch/1.0 (+local inventory tool)"
TIMEOUT = 25

# 这几种状态代表卖家此刻在游戏里，报价可信；offline 的挂单可能一周没人理
LIVE = {"ingame", "online"}


# ---------------------------------------------------------------- HTTP

def _get(url: str, retries: int = 3) -> dict:
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={
            "Accept": "application/json",
            "User-Agent": UA,
            "Accept-Encoding": "gzip",
        })
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.decompress(raw)
                return json.loads(raw)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return {}
            last = exc
            if exc.code in (429, 500, 502, 503, 504):
                time.sleep(1.5 * (attempt + 1) + random.random())
                continue
            raise
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last = exc
            time.sleep(1.0 * (attempt + 1) + random.random())
    raise RuntimeError(f"{url} 连续 {retries} 次失败: {last}")


# ---------------------------------------------------------------- 目录

def cmd_items(args) -> int:
    os.makedirs(MARKET_DIR, exist_ok=True)
    payload = _get(f"{API}/items")
    data = payload.get("data") or []
    slim = [{"id": x["id"], "slug": x["slug"], "ref": x.get("gameRef"),
             "tags": x.get("tags") or [], "ducats": x.get("ducats")}
            for x in data]
    doc = {"ts": _now(), "apiVersion": payload.get("apiVersion"), "items": slim}
    with open(ITEMS_PATH, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"items {len(slim)} 项 -> {ITEMS_PATH} ({os.path.getsize(ITEMS_PATH)//1024} KB)")
    return 0


def load_items() -> dict:
    if not os.path.exists(ITEMS_PATH):
        raise SystemExit("先跑 `wf_market.py items` 拉目录")
    with open(ITEMS_PATH, encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------- 目标清单

def alias_ref(ref: str) -> str | None:
    """market 部件是 Blueprint，套装字典是 Component，两边都要能查。"""
    for suffix, other in (("Component", "Blueprint"), ("Blueprint", "Component")):
        if ref.endswith(suffix):
            return ref[: -len(suffix)] + other
    return None


def build_targets() -> dict[str, dict]:
    """从背包视图里挑出值得抓价的对象。

    返回 {key: {"slug":..., "kind": set|part|relic, ...}}，key 用 slug 保持唯一。
    """
    items = load_items()["items"]
    by_ref: dict[str, dict] = {}
    for x in items:
        if x["ref"]:
            by_ref.setdefault(x["ref"], x)

    with open(VIEW_PATH, encoding="utf-8") as fh:
        view = json.load(fh)

    targets: dict[str, dict] = {}

    def add(entry: dict | None, kind: str, meta: dict) -> None:
        if not entry:
            return
        slot = targets.setdefault(entry["slug"], {"kind": kind, "id": entry["id"],
                                                 "ref": entry["ref"], **meta})

    for s in view["sets"]:
        add(by_ref.get(s["id"]), "set", {"setId": s["id"], "name": s["name"]})
        for p in s["parts"]:
            entry = by_ref.get(p["id"]) or by_ref.get(alias_ref(p["id"]) or "")
            add(entry, "part", {"setId": s["id"]})

    # 遗物在 market 里按代号聚合，没有精炼档；view.json 已经存了任取的一个
    # uniqueName 在 `ref` 上。它带 Bronze/Silver/Gold/Platinum 后缀（对应四档
    # 精炼），market 的 gameRef 不带，查之前要去掉。
    for r in view["relics"]:
        ref = r.get("ref")
        if not ref:
            continue
        base = ref
        for suffix in ("Bronze", "Silver", "Gold", "Platinum",
                       "Intact", "Exceptional", "Flawless", "Radiant"):
            if base.endswith(suffix):
                base = base[: -len(suffix)]
                break
        add(by_ref.get(base) or by_ref.get(ref), "relic", {"relicId": r["id"]})

    # 当期 Aya 商店的遗物：用户很可能一张都没有，价格照样要查，
    # 否则没法判断「这期值不值得用 Aya 换」。
    if os.path.exists(AYA_CACHE):
        try:
            with open(AYA_CACHE, encoding="utf-8") as fh:
                shop = json.load(fh)
            for row in shop.get("relics") or []:
                ref = (row.get("ref") or "").replace("/StoreItems/", "/")
                for suffix in ("Bronze", "Silver", "Gold", "Platinum"):
                    if ref.endswith(suffix):
                        ref = ref[: -len(suffix)]
                        break
                add(by_ref.get(ref), "relic", {"relicId": row.get("item")})
        except (OSError, json.JSONDecodeError):
            pass

    return targets


# ---------------------------------------------------------------- 抓价

def summarize(payload: dict) -> dict:
    orders = payload.get("data") or []
    if not orders:
        return {}
    sell_online, sell_all, buy_all = [], [], []
    online_sellers = 0
    sellers = 0
    for o in orders:
        if not o.get("visible", True):
            continue
        price = o.get("platinum")
        if not isinstance(price, int) or price <= 0:
            continue
        status = ((o.get("user") or {}).get("status") or "").lower()
        if o.get("type") == "sell":
            sellers += 1
            if status in LIVE:
                online_sellers += 1
                sell_online.append(price)
            sell_all.append(price)
        elif o.get("type") == "buy":
            buy_all.append(price)
    out = {}
    if sell_online:
        sell_online.sort()
        out["sellOnline"] = sell_online[0]
        # 有人挂 1p 骗点击，最低挂单会严重失真；中位数用来判断最低价是不是离群
        out["onlineMed"] = sell_online[len(sell_online) // 2]
    if sell_all:
        sell_all.sort()
        out["sellMin"] = sell_all[0]
    if buy_all:
        out["buyMax"] = max(buy_all)
    out["sellers"] = sellers
    out["online"] = online_sellers
    return out


_lock = threading.Lock()
_done = 0


def fetch_one(slug: str, item_id: str) -> tuple[str, dict]:
    global _done
    try:
        result = summarize(_get(f"{API}/orders/item/{item_id}"))
    except Exception as exc:                                    # noqa: BLE001
        result = {"error": str(exc)[:120]}
    with _lock:
        _done += 1
        if _done % 25 == 0 or _done == 1:
            sys.stderr.write(f"\r  {_done} 件已抓")
            sys.stderr.flush()
    return slug, result


def cmd_sync(args) -> int:
    targets = build_targets()
    if args.limit:
        # 先抓套装（最有决策价值），再抓部件
        ordered = sorted(targets.items(), key=lambda kv: 0 if kv[1]["kind"] == "set" else 1)
        targets = dict(ordered[: args.limit])
    print(f"目标 {len(targets)} 件（套装 {sum(1 for t in targets.values() if t['kind']=='set')} / "
          f"部件 {sum(1 for t in targets.values() if t['kind']=='part')} / "
          f"遗物 {sum(1 for t in targets.values() if t['kind']=='relic')}）")

    old = {}
    if os.path.exists(PRICES_PATH):
        with open(PRICES_PATH, encoding="utf-8") as fh:
            old = json.load(fh).get("items") or {}

    if args.missing:
        targets = {k: v for k, v in targets.items() if k not in old}
        print(f"只补缺：还剩 {len(targets)} 件")
        if not targets:
            print("没有要抓的")
            return 0

    prices: dict[str, dict] = dict(old)
    started = time.time()
    with futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(fetch_one, slug, t["id"]): slug for slug, t in targets.items()}
        for job in futures.as_completed(jobs):
            slug, result = job.result()
            if result:
                prices[slug] = {**result, "ts": _now()}

    sys.stderr.write("\r" + " " * 30 + "\r")
    doc = {"ts": _now(), "source": "api.warframe.market/v2", "items": prices}
    os.makedirs(MARKET_DIR, exist_ok=True)
    with open(PRICES_PATH, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))

    errored = sum(1 for v in prices.values() if v.get("error"))
    print(f"{len(prices)} 件有价（失败 {errored}）  "
          f"{time.time()-started:.0f}s  {os.path.getsize(PRICES_PATH)//1024} KB")
    return 0


# ---------------------------------------------------------------- 报告

def cmd_report(args) -> int:
    with open(PRICES_PATH, encoding="utf-8") as fh:
        price_doc = json.load(fh)
    prices = price_doc["items"]
    items = {x["slug"]: x for x in load_items()["items"]}
    by_ref = {}
    for x in items.values():
        if x["ref"]:
            by_ref.setdefault(x["ref"], x)

    def quote(ref: str) -> dict:
        entry = by_ref.get(ref) or by_ref.get(alias_ref(ref) or "")
        if not entry:
            return {}
        return prices.get(entry["slug"]) or {}

    def unit(p: dict) -> int:
        return p.get("sellOnline") or p.get("sellMin") or 0

    with open(VIEW_PATH, encoding="utf-8") as fh:
        view = json.load(fh)

    print(f"价格快照 {price_doc['ts']}\n")

    rows = []
    total_loose = 0
    for s in view["sets"]:
        sp = quote(s["id"])
        set_price = unit(sp)
        parts_total = 0
        loose = 0
        for p in s["parts"]:
            pp = quote(p["id"])
            up = unit(pp)
            parts_total += up
            if s["status"] == "owned":
                loose += p["count"] * up
            elif p["count"] > 1:
                loose += (p["count"] - 1) * up
        total_loose += loose
        rows.append({
            "name": s["zh"], "en": s["name"], "status": s["status"],
            "missing": s["missing"], "total": s["total"],
            "set": set_price, "parts": parts_total, "loose": loose,
            "have": s["haveCount"],
        })

    worth = sorted([r for r in rows if r["loose"] > 0], key=lambda r: -r["loose"])
    print(f"散件可变现合计 {total_loose} p")
    print("最值钱的 12 组：")
    for r in worth[:12]:
        print(f"  {r['name']:22s} {r['status']:7s} 余件 {r['loose']:5d} p")

    print("\n拆卖 vs 整卖（已成套，摘要有套价的）：")
    cmp_rows = [r for r in rows if r["status"] == "owned" and r["set"] and r["parts"]]
    for r in sorted(cmp_rows, key=lambda r: -(r["parts"] - r["set"]))[:10]:
        diff = r["parts"] - r["set"]
        print(f"  {r['name']:22s} 成品 {r['set']:4d} p   拆件 {r['parts']:4d} p   差 {diff:+4d}")

    print("\n缺口小且套价高的（值得凑）：")
    near = [r for r in rows if r["status"] == "missing" and r["missing"] <= 2 and r["set"]]
    for r in sorted(near, key=lambda r: -r["set"])[:10]:
        print(f"  {r['name']:22s} 缺 {r['missing']}/{r['total']}  套价 {r['set']:4d} p")
    return 0


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    ap = argparse.ArgumentParser(description="warframe.market 价格抓取")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("items", help="拉商品目录").set_defaults(func=cmd_items)

    s = sub.add_parser("sync", help="抓价格")
    s.add_argument("--limit", type=int, default=0, help="只抓前 N 件，用于试跑")
    s.add_argument("--workers", type=int, default=4, help="并发数，默认 4")
    s.add_argument("--missing", action="store_true", help="只抓还没有价格的")
    s.set_defaults(func=cmd_sync)

    sub.add_parser("report", help="按背包算持仓价值").set_defaults(func=cmd_report)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
