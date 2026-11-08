#!/usr/bin/env python3
"""把套装和遗物的缩略图下到 Asset Catalog 里，供 App 直接当素材用。

图源是 warframe.market 的静态 CDN（图片本身是 DE 的游戏资产）：
    https://warframe.market/static/assets/<icon>
v2 `/items` 的 `i18n.en.thumb` 就是 `items/images/en/thumbs/<slug>.<hash>.128x128.png`。
128×128 一张 12 KB 左右，列表里显示 40 pt，够用且不会把 IPA 撑大。

去重：所有 Axi 遗物共用同一张图（hash 相同），所以按内容 hash 命名，
162 个套装 + 76 个遗物代号最后只有 ~168 个 imageset。

输出
    WarframeWatch/Resources/Assets.xcassets/Icons/<name>.imageset/
    data/market/icons.json            {slug: assetName}

DE 的内容政策允许非商业粉丝项目使用 Warframe 资产；这个 App 不收费、不分发。
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW = os.path.join(ROOT, "data", "inventory", "view.json")
ITEMS_FULL = os.path.join(ROOT, "data", "market", "items_full.json")
ICONS_OUT = os.path.join(ROOT, "data", "market", "icons.json")
CATALOG = os.path.join(ROOT, "WarframeWatch", "Resources", "Assets.xcassets", "Icons")

API = "https://api.warframe.market/v2/items"
CDN = "https://warframe.market/static/assets/"
UA = "WarframeWatch/1.0 (personal fan app)"

CONTENTS = {
    "images": [{"filename": None, "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
}

HASH = re.compile(r"\.([0-9a-f]{16,})\.", re.I)


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def fetch_items() -> list:
    """items 有 1.6 MB，拉一次存下来；重跑脚本不重复下载。"""
    if os.path.exists(ITEMS_FULL):
        return load_json(ITEMS_FULL)["data"]
    req = urllib.request.Request(API, headers={
        "Accept": "application/json", "Language": "en", "Platform": "pc", "User-Agent": UA,
    })
    with urllib.request.urlopen(req, timeout=40) as resp:
        payload = json.loads(resp.read())
    os.makedirs(os.path.dirname(ITEMS_FULL), exist_ok=True)
    with open(ITEMS_FULL, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False)
    return payload["data"]


def relic_base(ref: str) -> str:
    for suffix in ("Bronze", "Silver", "Gold", "Platinum"):
        if ref.endswith(suffix):
            return ref[: -len(suffix)]
    return ref


def pick(by_ref: dict, ref: str, tag: str):
    for entry in by_ref.get(ref, []):
        if tag in entry.get("tags", []):
            return entry
    return None


def thumb_of(entry: dict) -> str | None:
    i18n = entry.get("i18n") or {}
    for lang in ("en", "zh-hans"):
        node = i18n.get(lang) or {}
        if node.get("thumb"):
            return node["thumb"]
        if node.get("icon"):
            return node["icon"]
    return None


def download(url: str, dest: str) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    with open(dest, "wb") as fh:
        fh.write(data)
    return len(data)


def build() -> int:
    view = load_json(VIEW)
    items = fetch_items()

    by_ref = {}
    for entry in items:
        ref = entry.get("gameRef")
        if ref:
            by_ref.setdefault(ref, []).append(entry)

    # (slug, 类别, market ref) —— 顺序稳定，便于 diff
    wanted = []
    for s in view["sets"]:
        hit = pick(by_ref, s["id"], "set")
        if hit:
            wanted.append((hit["slug"], hit))
    for r in view["relics"]:
        ref = relic_base(r.get("ref") or "")
        hit = pick(by_ref, ref, "relic") if ref else None
        if hit:
            wanted.append((hit["slug"], hit))

    os.makedirs(CATALOG, exist_ok=True)
    by_hash = {}
    mapping = {}
    eras = {}
    total = 0
    saved = 0

    for slug, entry in wanted:
        thumb = thumb_of(entry)
        if not thumb:
            continue
        match = HASH.search(thumb)
        # 同 hash 就是同一张图：76 个遗物代号只会落成 10 张（按纪元）
        key = ("relic_" + match.group(1)[:8]) if match and "relic" in entry["tags"] else slug
        # App 端数据里同时带远程路径，本地缺图（数据比 App 新）时还能显示
        mapping[slug] = {"a": key, "u": thumb}
        if "relic" in entry["tags"]:
            eras.setdefault(slug.split("_")[0], key)
        if key in by_hash:
            continue
        by_hash[key] = True

        folder = os.path.join(CATALOG, key + ".imageset")
        os.makedirs(folder, exist_ok=True)
        dest = os.path.join(folder, key + ".png")
        if not os.path.exists(dest):
            try:
                size = download(CDN + thumb, dest)
            except Exception as exc:                          # noqa: BLE001
                print(f"  跳过 {slug}：{exc}")
                os.rmdir(folder)
                mapping.pop(slug, None)
                continue
            total += size
            saved += 1
        meta = dict(CONTENTS)
        meta["images"] = [{"filename": key + ".png", "idiom": "universal"}]
        with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as fh:
            json.dump(meta, fh, indent=2)

    with open(ICONS_OUT, "w", encoding="utf-8") as fh:
        json.dump({"slugs": mapping, "eras": eras}, fh, ensure_ascii=False, indent=0, sort_keys=True)

    print(f"套装 {len(view['sets'])} · 遗物 {len(view['relics'])} → 图片 {len(by_hash)} 张")
    print(f"纪元图 {len(eras)} 张：{', '.join(sorted(eras))}")
    print(f"新下载 {saved} 张 / {total // 1024} KB")
    print(f"-> {CATALOG}")
    print(f"-> {ICONS_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(build())
