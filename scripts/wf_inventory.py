#!/usr/bin/env python3
"""Read the full account inventory out of AlecaFrame's local cache.

Why this and not the network
----------------------------
DE serves `api/inventory.php?accountId=..&nonce=..`, and those two values sit in
the running client's memory. Using them works, but it reuses the game's own
session token: whether DE rotates the nonce on read is not observable from
outside, and if it does, the client's next request goes out with a dead token
and the player drops. A data source that can silently log you out is not a data
source.

`lastData.dat` avoids all of it. AlecaFrame reads the inventory from the game
and writes it here; the format is AES-128-CBC-PKCS7 with a static key that
Sainan published in `alecaframe-inventory-parser`. Nothing is sent anywhere and
the game process is never touched, so there is nothing to race and nothing to
expire.

Two file shapes exist historically: the inventory object stored directly, and an
older wrapper with the object as a JSON string under `InventoryJson`. Both are
handled.

Usage
-----
    python scripts/wf_inventory.py read            # decrypt, snapshot, summarize
    python scripts/wf_inventory.py summary         # re-print latest snapshot
    python scripts/wf_inventory.py export --format csv

Requires `cryptography`.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

DEFAULT_DAT = os.path.join(os.environ.get("LOCALAPPDATA", ""), "AlecaFrame", "lastData.dat")
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "inventory")

# Published by Sainan/alecaframe-inventory-parser (script.pluto). 16 bytes each.
KEY = b"LEO-ALEC\tEO-ALEC"
IV = bytes([49, 50, 70, 71, 66, 51, 54, 45, 76, 69, 51, 45, 113, 61, 57, 0])

# Gear entries are unique per instance: one row, no stack count, progress lives
# in XPInfo keyed by the same ItemType.
GEAR_KEYS = (
    "Suits", "LongGuns", "Pistols", "Melee", "SpaceSuits", "SpaceGuns",
    "SpaceMelee", "Sentinels", "SentinelWeapons", "MoaPets", "KubrowPets",
    "OperatorAmps", "OperatorSuits", "MechSuits", "Ships", "CrewShips",
    "CrewMembers", "Horses", "Motorcycles", "DataKnives", "Scoops",
)

# Bins hold the same gear entries for loadout presets; they duplicate the lists
# above, so they are deliberately not flattened.
STACK_KEYS = (
    "MiscItems", "Recipes", "Consumables", "RawUpgrades", "Resources",
    "SpecialItems", "FlavourItems", "ShipDecorations", "WeaponSkins",
)

CREDITS = ("RegularCredits", "PremiumCredits", "FusionPoints")


# --- Crypto ---------------------------------------------------------------

def _aes():
    try:
        from cryptography.hazmat.primitives import padding
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    except ImportError:  # pragma: no cover - environment problem, not logic
        raise SystemExit("需要 cryptography：pip install cryptography")
    return Cipher, algorithms, modes, padding


def decrypt(raw: bytes) -> bytes:
    Cipher, algorithms, modes, padding = _aes()
    dec = Cipher(algorithms.AES(KEY), modes.CBC(IV)).decryptor()
    padded = dec.update(raw) + dec.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    try:
        return unpadder.update(padded) + unpadder.finalize()
    except ValueError as exc:
        raise ValueError(f"padding 非法（文件可能被截断）：{exc}") from None


def load_lastdata(path=DEFAULT_DAT, attempts=4) -> dict:
    """Decrypt and parse, tolerating a write that lands mid-read.

    AlecaFrame rewrites this file while running, so a read can catch it
    half-written. A truncated file usually fails padding or JSON; both are worth
    one more try before giving up.
    """
    if not os.path.exists(path):
        raise SystemExit(f"找不到 {path}。AlecaFrame 至少要运行过一次。")

    last_error = None
    for attempt in range(attempts):
        with open(path, "rb") as fh:
            raw = fh.read()
        if len(raw) % 16:
            last_error = f"长度 {len(raw)} 不是 16 的倍数"
        else:
            try:
                data = json.loads(decrypt(raw))
                if isinstance(data, dict) and isinstance(data.get("InventoryJson"), str):
                    data = json.loads(data["InventoryJson"])
                return data
            except (json.JSONDecodeError, SystemExit, ValueError) as exc:
                last_error = str(exc)
        if attempt + 1 < attempts:
            time.sleep(0.4)

    raise SystemExit(f"读取 {path} 失败（重试 {attempts} 次）：{last_error}")


# --- Flatten --------------------------------------------------------------

def _short_name(item_type: str) -> str:
    """Last path segment, split on case boundaries: MesaPrime -> Mesa Prime."""
    if not item_type:
        return ""
    tail = item_type.rstrip("/").rsplit("/", 1)[-1]
    tail = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", tail)
    tail = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", " ", tail)
    return tail.replace("_", " ").strip()


def _mod_level(entry) -> int | None:
    fingerprint = entry.get("UpgradeFingerprint")
    if not isinstance(fingerprint, str):
        return None
    try:
        return int(json.loads(fingerprint).get("lvl"))
    except (json.JSONDecodeError, TypeError, ValueError):
        return None


def flatten(data: dict):
    """Return (state, items). items is one flat row per stack or per instance."""
    xp_by_type = {}
    for entry in data.get("XPInfo", []) or []:
        item_type = entry.get("ItemType")
        if item_type:
            xp_by_type[item_type] = xp_by_type.get(item_type, 0) + int(entry.get("XP") or 0)

    items = []

    for key in GEAR_KEYS:
        for entry in data.get(key, []) or []:
            item_type = entry.get("ItemType")
            if not item_type:
                continue
            items.append({
                "cat": key,
                "type": item_type,
                "name": _short_name(item_type),
                "count": 1,
                "rank": None,
                "xp": xp_by_type.get(item_type),
            })

    for entry in data.get("Upgrades", []) or []:
        item_type = entry.get("ItemType")
        if not item_type:
            continue
        items.append({
            "cat": "Upgrades",
            "type": item_type,
            "name": _short_name(item_type),
            "count": 1,
            "rank": _mod_level(entry),
            "xp": None,
        })

    for key in STACK_KEYS:
        for entry in data.get(key, []) or []:
            item_type = entry.get("ItemType")
            if not item_type:
                continue
            # Relics live inside MiscItems; splitting them out is what makes
            # "which relics do I still have" answerable.
            cat = "Relics" if "/Projections/" in item_type else key
            # Cosmetics and skins carry no ItemCount at all; they are single
            # instances, not zero of something.
            raw_count = entry.get("ItemCount")
            items.append({
                "cat": cat,
                "type": item_type,
                "name": _short_name(item_type),
                "count": 1 if raw_count is None else int(raw_count),
                "rank": None,
                "xp": None,
            })

    state = {
        "mastery_rank": data.get("PlayerLevel"),
        "credits": data.get("RegularCredits"),
        "platinum": data.get("PremiumCredits"),
        "endo": data.get("FusionPoints"),
        "trades_remaining": data.get("TradesRemaining"),
        "created_ms": _extract_date(data.get("Created")),
        "last_sync_ms": _oid_time_ms(data.get("LastInventorySync")),
        "mission_clears": len(data.get("Missions", []) or []),
        "top_level_keys": len(data),
    }
    return state, items


def _extract_date(node):
    if isinstance(node, dict):
        value = node.get("$date")
        if isinstance(value, dict):
            raw = value.get("$numberLong")
            if raw is not None:
                return int(raw)
        if isinstance(value, (int, float)):
            return int(value)
    return None


def _oid_time_ms(node):
    """Mongo ObjectId embeds a unix timestamp in its first four bytes."""
    if isinstance(node, dict):
        oid = node.get("$oid")
        if isinstance(oid, str) and len(oid) >= 8:
            try:
                return int(oid[:8], 16) * 1000
            except ValueError:
                return None
    return None


# --- Output ---------------------------------------------------------------

def _iso(ms):
    if not ms:
        return "-"
    return datetime.fromtimestamp(ms / 1000, timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M")


def summarize(state, items):
    by_cat = {}
    for row in items:
        bucket = by_cat.setdefault(row["cat"], {"rows": 0, "units": 0})
        bucket["rows"] += 1
        bucket["units"] += row["count"]

    lines = []
    lines.append(f"精通等级 {state['mastery_rank']}   白金 {state['platinum']:,}   "
                 f"星币 {state['credits']:,}   内融核心 {state['endo']:,}")
    lines.append(f"账号创建 {_iso(state['created_ms'])}   背包同步 {_iso(state['last_sync_ms'])}   "
                 f"已完成节点 {state['mission_clears']}")
    lines.append("")
    for cat, bucket in sorted(by_cat.items(), key=lambda kv: -kv[1]["rows"]):
        extra = "" if bucket["units"] == bucket["rows"] else f"   共 {bucket['units']:,} 件"
        lines.append(f"  {cat:20s} {bucket['rows']:5d} 行{extra}")
    lines.append("")
    lines.append(f"合计 {len(items)} 行")
    return "\n".join(lines)


def save_snapshot(data, state, items, out_dir=DEFAULT_OUT):
    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode()
    slim = json.dumps({"state": state, "items": items},
                      ensure_ascii=False, separators=(",", ":")).encode()

    for name, blob in ((f"{stamp}.json.gz", raw), ("latest.json.gz", raw),
                       ("items.json.gz", slim)):
        with gzip.open(os.path.join(out_dir, name), "wb", compresslevel=9) as fh:
            fh.write(blob)

    meta = {
        "captured_at": stamp,
        "bytes_raw": len(raw),
        "bytes_slim": len(slim),
        "sha256_16": hashlib.sha256(raw).hexdigest()[:16],
        "state": state,
        "item_rows": len(items),
    }
    with open(os.path.join(out_dir, "latest.meta.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)
    return meta


def load_latest(out_dir=DEFAULT_OUT):
    path = os.path.join(out_dir, "items.json.gz")
    if not os.path.exists(path):
        return None
    with gzip.open(path, "rb") as fh:
        payload = json.loads(fh.read())
    return payload["state"], payload["items"]


# --- CLI ------------------------------------------------------------------

def cmd_read(args):
    data = load_lastdata(args.dat)
    state, items = flatten(data)
    meta = save_snapshot(data, state, items, args.out)
    print(f"已读 {args.dat}")
    print(f"  明文 {meta['bytes_raw']:,} B，精简 {meta['bytes_slim']:,} B，sha {meta['sha256_16']}")
    print()
    print(summarize(state, items))
    return 0


def cmd_summary(args):
    loaded = load_latest(args.out)
    if loaded is None:
        print(f"{args.out} 下没有快照，先跑 read。")
        return 1
    state, items = loaded
    meta_path = os.path.join(args.out, "latest.meta.json")
    if os.path.exists(meta_path):
        with open(meta_path, encoding="utf-8") as fh:
            print(f"快照 {json.load(fh)['captured_at']}")
            print()
    print(summarize(state, items))
    return 0


def cmd_export(args):
    loaded = load_latest(args.out)
    if loaded is None:
        print(f"{args.out} 下没有快照，先跑 read。")
        return 1
    _, items = loaded
    if args.cat:
        wanted = {c.lower() for c in args.cat}
        items = [row for row in items if row["cat"].lower() in wanted]
    items = sorted(items, key=lambda r: (r["cat"], r["name"]))

    if args.format == "csv":
        writer = csv.DictWriter(sys.stdout, fieldnames=["cat", "name", "count", "rank", "xp", "type"])
        writer.writeheader()
        writer.writerows(items)
    else:
        for row in items:
            print(json.dumps(row, ensure_ascii=False))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="从 AlecaFrame 本地缓存读完整背包")
    parser.add_argument("--out", default=DEFAULT_OUT, help="快照目录")
    parser.add_argument("--dat", default=DEFAULT_DAT, help="lastData.dat 路径")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("read", help="解密并落快照").set_defaults(func=cmd_read)
    sub.add_parser("summary", help="打印最近快照摘要").set_defaults(func=cmd_summary)

    p_export = sub.add_parser("export", help="导出扁平清单")
    p_export.add_argument("--format", choices=("csv", "jsonl"), default="csv")
    p_export.add_argument("--cat", nargs="*", help="只导出这些分类")
    p_export.set_defaults(func=cmd_export)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
