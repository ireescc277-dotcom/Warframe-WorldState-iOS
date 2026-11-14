#!/usr/bin/env python3
"""从真实快照裁一份可以进仓库的样例。

仓库要公开，而 `InventoryData.json` 里是账号数据：白金余额、星币、
每个 Prime 部件各剩几件。这些东西不该跟着源码一起出门。

所以真实文件留在本地（`.gitignore` 里），仓库里只有这份样例：
条目裁到 14 套 + 12 个遗物，余额归零，总量按裁剪后的数据重算。
CI 打包和截图都用它，装到手机上之后由 App 自己从 VPS 拉真数据覆盖。
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.json")
OUT = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.sample.json")

SETS = 15
RELICS = 12
AYA = 4


def pick_sets(all_sets: list) -> list:
    """三种状态都要有，截图才看得出 UI 怎么区分它们。"""
    owned = [s for s in all_sets if s["status"] == "owned"]
    ready = [s for s in all_sets if s["status"] == "ready"]
    missing = sorted([s for s in all_sets if s["status"] == "missing"],
                     key=lambda s: (s["total"] - s["have"], -s["setPrice"]))
    return owned[:8] + ready[:2] + missing[:5]


def build() -> dict:
    with open(SRC, encoding="utf-8") as fh:
        doc = json.load(fh)

    sets = pick_sets(doc["sets"])
    relics = doc["relics"][:RELICS]
    aya = doc["aya"]
    aya["items"] = aya["items"][:AYA]
    sample_ducats = sum(p["n"] * p["d"] for s in sets for p in s["parts"])
    prime_part_units = sum(p["n"] for s in sets for p in s["parts"])
    priced_prime_part_units = sum(
        p["n"] for s in sets for p in s["parts"] if p["p"] > 0
    )
    all_plat = sum(p["n"] * p["p"] for s in sets for p in s["parts"])

    return {
        # 样例不携带真实快照的 hash 或武器实例；远端版本切换只看 manifest，
        # 不再拿这个 legacy builtAt 和真实数据抢“新旧”。
        "builtAt": "2020-01-01T00:00:00Z",
        "marketAt": doc.get("marketAt"),
        # 余额不是样例要展示的东西，留着只会把真数写进公开仓库
        "profile": {"mr": 30, "plat": 0, "credits": 0, "sync": doc["profile"].get("sync")},
        "totals": {
            "setsOwned": sum(1 for s in sets if s["status"] == "owned"),
            "setsReady": sum(1 for s in sets if s["status"] == "ready"),
            "setsClose": sum(1 for s in sets if s["status"] == "missing" and s["loose"] == 0
                             and s["total"] - s["have"] <= 2),
            "setsAll": len(sets),
            "allPlat": all_plat,
            "primePartUnits": prime_part_units,
            "pricedPrimePartUnits": priced_prime_part_units,
            "loosePlat": sum(s["loose"] for s in sets),
            "allDucats": sample_ducats,
            "looseDucats": sample_ducats,
            "relicKinds": len(relics),
            "relicUnits": sum(r["n"] for r in relics),
            "mods": 0,
        },
        "aya": aya,
        "sets": sets,
        "relics": relics,
        "ownedWeapons": [],
        "ownedWarframes": [],
        "ownedCompanions": [],
        "ownedCompanionWeapons": [],
        "ownedArchwings": [],
        "equippedGear": [],
        "loadouts": [],
    }


def main() -> int:
    if not os.path.exists(SRC):
        print("没有真实快照，先跑 build_app_inventory.py", file=sys.stderr)
        return 1
    doc = build()
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"套装 {len(doc['sets'])} · 遗物 {len(doc['relics'])} · Aya {len(doc['aya']['items'])}")
    print(f"-> {OUT}  {os.path.getsize(OUT) // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
