#!/usr/bin/env python3
"""Create the public, synthetic account payload used by iOS visual CI.

The production account snapshot is deliberately never committed to this
repository.  The ordinary public sample consequently has no owned Arsenal
items.  That is appropriate for release builds, but it would make a screenshot
of the Arsenal configuration route prove nothing: there would be no weapon to
open.

This helper starts from that same sanitized sample and inserts a small,
entirely fictional loadout.  The fixture has an owned Torid, a current Gauss
Prime configuration, and two possible external casters (Rhino's Roar and
Volt's Shock Trooper).  It contains no DE account identifier, no item instance
identifier, and no user-owned configuration.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def strength_upgrade(slot: int, name: str, value: float, *, rank: int = 5,
                     max_rank: int = 5, weapon_buff_scale: float | None = None) -> dict:
    row: dict = {
        "s": slot,
        "n": name,
        "r": rank,
        "m": max_rank,
        "k": "Mod",
        "st": [{"l": name, "v": value, "k": "base"}],
        "sr": [],
    }
    if weapon_buff_scale is not None:
        row["wb"] = weapon_buff_scale
    return row


def frame(
    identifier: str,
    name: str,
    abilities: list[tuple[int, str]],
    upgrades: list[dict],
    *,
    shards: list[dict] | None = None,
) -> dict:
    return {
        "id": identifier,
        "z": name,
        "a": [{"o": ordinal, "n": ability} for ordinal, ability in abilities],
        "cfg": [{"l": "A", "u": upgrades, "exact": True, "issues": []}],
        "sh": shards or [],
    }


def build_fixture(source: Path) -> dict:
    data = json.loads(source.read_text(encoding="utf-8"))

    # These stable IDs are fixture-only labels, not values obtained from DE.
    data["source"] = {
        "accountHash": "0" * 64,
        "accountSync": "2020-01-01T00:00:00Z",
    }
    data["ownedWeapons"] = [{
        "id": "visual-torid",
        "n": "Torid",
        "z": "Torid（视觉测试）",
        "c": "Primary",
        "k": "LongGuns",
        "p": {"Toxin": 0.25},
        "inc": [],
        "cfg": [
            {
                "l": "A",
                "s": [
                    "Serration", "Galvanized Chamber", "Critical Delay",
                    "Vital Sense", "Malignant Force", "Rime Rounds",
                    "Hunter Munitions", "Primed Firestorm", None, None,
                    "Primary Merciless",
                ],
                "exact": True,
                "issues": [],
            },
            {
                "l": "B",
                "s": [
                    "Serration", "Split Chamber", "Point Strike", "Vital Sense",
                    "Malignant Force", "Rime Rounds", None, None, None, None,
                    "Primary Merciless",
                ],
                "exact": True,
                "issues": [],
            },
        ],
    }]

    data["ownedWarframes"] = [
        frame(
            "visual-gauss-prime",
            "Gauss Prime（视觉测试）",
            [(1, "Mach Rush"), (2, "Kinetic Plating"), (3, "Thermal Sunder"), (4, "Redline")],
            [
                strength_upgrade(0, "Intensify", 0.30),
                strength_upgrade(1, "Augur Secrets", 0.24),
            ],
            shards=[{"s": 0, "n": "猩红执政官石", "as": 0.10, "tau": False}],
        ),
        frame(
            "visual-rhino-prime",
            "Rhino Prime（外部施法测试）",
            [(1, "Rhino Charge"), (2, "Iron Skin"), (3, "Roar"), (4, "Rhino Stomp")],
            [
                strength_upgrade(0, "Blind Rage", 0.99, rank=8, max_rank=10),
                strength_upgrade(1, "Transient Fortitude", 0.55, rank=10, max_rank=10),
            ],
        ),
        frame(
            "visual-volt-prime",
            "Volt Prime（外部施法测试）",
            [(1, "Shock"), (2, "Speed"), (3, "Electric Shield"), (4, "Discharge")],
            [
                strength_upgrade(0, "Intensify", 0.30),
                strength_upgrade(1, "Shock Trooper", 0.0, rank=3, max_rank=3,
                                 weapon_buff_scale=1.0),
            ],
        ),
    ]
    data["loadouts"] = [{
        "id": "visual-loadout",
        "n": "视觉验证配置",
        "fav": True,
        "active": True,
        "slots": [
            {"r": "warframe", "i": "visual-gauss-prime", "z": "Gauss Prime（视觉测试）", "c": 0},
            {"r": "primary", "i": "visual-torid", "z": "Torid（视觉测试）", "c": 0},
            {"r": "secondary", "z": "未装备"},
            {"r": "melee", "z": "未装备"},
            {"r": "heavy", "z": "未装备"},
        ],
    }]
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description="生成不含账号资料的军械库视觉测试夹具")
    parser.add_argument("--input", required=True, type=Path, help="公开脱敏样例 JSON")
    parser.add_argument("--out", required=True, type=Path, help="写入的 CI 资源 JSON")
    args = parser.parse_args()

    data = build_fixture(args.input)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"visual Arsenal fixture -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
