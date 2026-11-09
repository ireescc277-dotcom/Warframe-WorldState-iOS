#!/usr/bin/env python3
"""给 VPS 上的通知进程生成节点中文名表。

recorder 用的 node_meta.json 只有 mt/planet，够算概率但不够写推送文案：
「SolNode85」没人看得懂，「Gaia（地球）· 拦截」才看得懂。

输出 data/nodes_zh.json：
    {"SolNode85": {"name": "Gaia", "planet": "地球", "task": "拦截", "mode": "MT_TERRITORY"}}
"""

from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "WarframeWatch", "Resources", "DefaultDict.json")
OUT = os.path.join(ROOT, "data", "nodes_zh.json")

# 词典里的 n 是「Galatea （海王星）」，把括号部分剥掉，行星单独存。
SUFFIX = re.compile(r"\s*[（(][^）)]*[）)]\s*$")


def main() -> int:
    with open(SRC, encoding="utf-8") as fh:
        payload = json.load(fh)
    nodes = payload.get("nodes") or {}

    out: dict[str, dict] = {}
    for node_id, info in nodes.items():
        if not isinstance(info, dict):
            continue
        raw = (info.get("n") or "").strip()
        if not raw:
            continue
        name = SUFFIX.sub("", raw).strip()
        out[node_id] = {
            "name": name,
            "planet": info.get("planet"),
            "task": info.get("t"),
            "mode": info.get("mt"),
        }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"{len(out)} nodes -> {OUT} ({size/1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
