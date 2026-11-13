"""Focused contract tests for account-snapshot configuration import.

Run directly so this stays dependency-free in the same CI environment that
builds the iOS payload:

    python3 scripts/test_build_app_inventory.py
"""

from __future__ import annotations

import json
import unittest

from build_app_inventory import (
    RIVEN_MAXIMUM,
    build_owned_weapons,
    damagekit_ranked_action_values,
    decode_riven,
    resolve_config_upgrade,
    source_stat_coefficients,
    source_proven_non_damage_reason,
    source_proven_whole_action_scale,
    upgrade_indexes,
)
from wf_gamedata import build_riven_tags


TYPE = "/Lotus/Upgrades/Mods/Rifle/WeaponDamageAmountMod"


def ranked_upgrade(rank: int) -> dict:
    return {
        "ItemId": f"ranked-{rank}",
        "ItemType": TYPE,
        "UpgradeFingerprint": json.dumps({"lvl": rank}),
    }


class ConfigUpgradeRankTests(unittest.TestCase):
    def resolve(self, inventory: dict):
        by_id, by_type, raw_counts = upgrade_indexes(inventory)
        return resolve_config_upgrade(TYPE, by_id, by_type, raw_counts)

    def test_raw_only_type_reference_is_an_exact_rank_zero_card(self):
        upgrade, rank, issue = self.resolve({
            "RawUpgrades": [{"ItemType": TYPE, "ItemCount": 2}],
            "Upgrades": [],
        })
        self.assertEqual(upgrade, {"ItemType": TYPE})
        self.assertEqual(rank, 0)
        self.assertIsNone(issue)

    def test_fingerprinted_only_type_reference_keeps_its_exact_rank(self):
        upgrade, rank, issue = self.resolve({
            "RawUpgrades": [],
            "Upgrades": [ranked_upgrade(3)],
        })
        self.assertEqual(upgrade, {"ItemType": TYPE})
        self.assertEqual(rank, 3)
        self.assertIsNone(issue)

    def test_raw_and_fingerprinted_copies_remain_ambiguous(self):
        # Configs that name only the Mod type do not say whether the equipped
        # card is the raw rank-0 copy or the separately fingerprinted rank-3
        # copy.  Choosing either would fabricate a damage value.
        upgrade, rank, issue = self.resolve({
            "RawUpgrades": [{"ItemType": TYPE, "ItemCount": 1}],
            "Upgrades": [ranked_upgrade(3)],
        })
        self.assertEqual(upgrade, {"ItemType": TYPE})
        self.assertIsNone(rank)
        self.assertIn("0/3", issue or "")

    def test_zero_count_raw_row_does_not_prove_rank_zero_exists(self):
        upgrade, rank, issue = self.resolve({
            "RawUpgrades": [{"ItemType": TYPE, "ItemCount": 0}],
            "Upgrades": [],
        })
        self.assertEqual(upgrade, {"ItemType": TYPE})
        self.assertIsNone(rank)
        self.assertIsNotNone(issue)


class WholeActionRankScaleTests(unittest.TestCase):
    def test_percent_text_cannot_backtrack_into_a_false_flat_value(self):
        self.assertEqual(source_stat_coefficients(["+48% Reload Speed"]), [0.48])

    def test_multi_stat_card_scales_only_when_every_action_value_has_source_proof(self):
        game_mod = {
            "lv": [
                ["+15% Radiation", "+10% Fire Rate"],
                ["+30% Radiation", "+20% Fire Rate"],
                ["+45% Radiation", "+30% Fire Rate"],
                ["+60% Radiation", "+40% Fire Rate"],
            ]
        }
        scale = source_proven_whole_action_scale(
            "Test Dual Stat", 0, 3, game_mod,
            {"Test Dual Stat": [0.6, 0.4]},
        )
        self.assertEqual(scale, 0.25)

    def test_unmatched_unknown_static_value_rejects_whole_card_scaling(self):
        # A card may not receive a blanket multiplier when an action value has
        # no exact source counterpart. `double_crit` is handled separately
        # below because it is a documented fixed Vigilante set effect.
        game_mod = {"lv": [["+0.3 Punch Through"], ["+1.5 Punch Through"]]}
        scale = source_proven_whole_action_scale(
            "Test Set Card", 0, 1, game_mod,
            {"Test Set Card": [1.5, 0.05]},
        )
        self.assertIsNone(scale)

    def test_vigilante_set_bonus_is_not_part_of_the_rank_scale(self):
        # DamageKit's fixed 5% per-equipped-card Vigilante set effect must
        # remain 5% even when the card itself is rank 0. The rank proof sees
        # only +Punch Through, which is the actual printed card stat.
        action_values = damagekit_ranked_action_values()
        self.assertEqual(action_values["Vigilante Offense"], [1.5])
        game_mod = {"lv": [["+0.3 Punch Through"], ["+1.5 Punch Through"]]}
        scale = source_proven_whole_action_scale(
            "Vigilante Offense", 0, 1, game_mod,
            {"Vigilante Offense": action_values["Vigilante Offense"]},
        )
        self.assertAlmostEqual(scale or -1, 0.2)

    def test_bow_specific_percent_branch_is_proven_without_a_generic_guess(self):
        # Fervor's source text explicitly prints the ordinary value and its
        # x2 Bow branch. It is not a generic multiplier parser.
        self.assertEqual(
            source_stat_coefficients(["+7.5% Fire Rate (x2 for Bows)"]),
            [0.075, 0.15],
        )
        game_mod = {
            "lv": [
                ["+7.5% Fire Rate (x2 for Bows)"],
                ["+45% Fire Rate (x2 for Bows)"],
            ]
        }
        action_values = damagekit_ranked_action_values()
        self.assertEqual(action_values["Vigilante Fervor"], [0.45, 0.45, 0.9])
        scale = source_proven_whole_action_scale(
            "Vigilante Fervor", 0, 1, game_mod,
            {"Vigilante Fervor": action_values["Vigilante Fervor"]},
        )
        self.assertAlmostEqual(scale or -1, 1.0 / 6.0)

    def test_faction_multiplier_normalizes_to_its_additive_action_bonus(self):
        game_mod = {"lv": [["x1.05 Damage to Grineer"], ["x1.3 Damage to Grineer"]]}
        scale = source_proven_whole_action_scale(
            "Test Faction", 0, 1, game_mod,
            {"Test Faction": [0.3, 0.3]},
        )
        self.assertAlmostEqual(scale or -1, 1.0 / 6.0)


class SourceProvenNonDamageTests(unittest.TestCase):
    def test_hush_requires_every_rank_line_to_remain_noise_only(self):
        reason = source_proven_non_damage_reason("Hush", {
            "lv": [
                ["Reduces the chance an enemy will hear gunfire by 25%."],
                ["Reduces the chance an enemy will hear gunfire by 100%."],
            ],
        })
        self.assertIn("听到枪声", reason or "")

    def test_mixed_or_unknown_source_text_stays_unresolved(self):
        self.assertIsNone(source_proven_non_damage_reason("Hush", {
            "lv": [
                ["Reduces the chance an enemy will hear gunfire by 25%."],
                ["+90% Damage"],
            ],
        }))
        self.assertIsNone(source_proven_non_damage_reason("Unknown", {
            "lv": [["+1.5 Range"]],
        }))

    def test_rank_ambiguous_hush_remains_visible_without_tainting_damage_result(self):
        weapon_type = "/Lotus/Weapons/Tenno/Rifle/Braton"
        hush_type = "/Lotus/Upgrades/Mods/Rifle/WeaponNoiseReductionMod"
        game_data = {
            "weapons": {
                weapon_type: {"n": "Braton", "z": "Braton"},
            },
            "mods": {
                hush_type: {
                    "n": "Hush",
                    "mx": 3,
                    "lv": [
                        ["Reduces the chance an enemy will hear gunfire by 25%."],
                        ["Reduces the chance an enemy will hear gunfire by 100%."],
                    ],
                },
            },
        }
        result = build_owned_weapons({
            "LongGuns": [{
                "ItemId": "test-braton",
                "ItemType": weapon_type,
                "Configs": [{"Upgrades": [hush_type]}],
            }],
            "Upgrades": [],
            "RawUpgrades": [],
        }, game_data_override=game_data)

        config = result[0]["cfg"][0]
        self.assertTrue(config["exact"])
        self.assertEqual(config["u"], [])
        self.assertEqual(config["s"][0], "Hush")
        self.assertEqual(config["nd"][0]["n"], "Hush")
        self.assertNotIn("r", config["nd"][0])
        self.assertIn("听到枪声", config["nd"][0]["why"])


class OfficialRivenTagTests(unittest.TestCase):
    def official_riven_tags(self) -> dict:
        return build_riven_tags([{
            "uniqueName": "/Lotus/Upgrades/Mods/Randomized/LotusPistolRandomModRare",
            "upgradeEntries": [
                {
                    "tag": "WeaponCorrosiveDamageMod",
                    "prefixTag": "cori",
                    "suffixTag": "or",
                    "upgradeValues": [{"value": 0.01}],
                },
                {
                    "tag": "WeaponGasDamageMod",
                    "prefixTag": "cali",
                    "suffixTag": "fel",
                    "upgradeValues": [{"value": 0.01}],
                },
                {
                    "tag": "WeaponViralDamageMod",
                    "prefixTag": "cari",
                    "suffixTag": "sco",
                    "upgradeValues": [{"value": 0.01}],
                },
                {
                    "tag": "WeaponRadiationDamageMod",
                    "prefixTag": "radi",
                    "suffixTag": "lo",
                    "upgradeValues": [{"value": 0.01}],
                },
                {
                    "tag": "WeaponMagneticDamageMod",
                    "prefixTag": "magni",
                    "suffixTag": "bra",
                    "upgradeValues": [{"value": 0.01}],
                },
                {
                    "tag": "WeaponBlastDamageMod",
                    "prefixTag": "fraga",
                    "suffixTag": "tus",
                    "upgradeValues": [{"value": 0.01}],
                },
            ],
        }])

    def test_official_upgrade_entries_keep_completed_element_tags(self):
        tags = self.official_riven_tags()
        entries = tags["LotusPistolRandomModRare"]
        by_tag = {entry["tag"]: entry for entry in entries}
        self.assertEqual(set(by_tag), {
            "WeaponBlastDamageMod", "WeaponCorrosiveDamageMod", "WeaponGasDamageMod",
            "WeaponMagneticDamageMod", "WeaponRadiationDamageMod", "WeaponViralDamageMod",
        })
        self.assertEqual(by_tag["WeaponCorrosiveDamageMod"]["value"], 0.01)
        self.assertEqual(by_tag["WeaponCorrosiveDamageMod"]["prefix"], "cori")
        self.assertEqual(by_tag["WeaponCorrosiveDamageMod"]["suffix"], "or")

    def test_completed_corrosive_riven_is_a_damage_component_not_unresolved(self):
        upgrade = {
            "ItemType": "/Lotus/Upgrades/Mods/Randomized/LotusPistolRandomModRare",
            "UpgradeFingerprint": json.dumps({
                "lvl": 8,
                "buffs": [{
                    "Tag": "WeaponCorrosiveDamageMod",
                    "Value": RIVEN_MAXIMUM,
                }],
                "curses": [],
            }),
        }
        riven, error = decode_riven(upgrade, {"om": 1.2}, self.official_riven_tags())

        self.assertIsNone(error)
        self.assertEqual(riven.get("unresolved"), None)
        self.assertAlmostEqual(riven["elements"]["corrosive"], 1.782)

    def test_owned_weapon_import_prefers_current_official_riven_tag_table(self):
        """A generated game-data cache, not the retired sidecar, drives import."""
        weapon_type = "/Lotus/Weapons/Test/Laetum"
        riven_type = "/Lotus/Upgrades/Mods/Randomized/LotusPistolRandomModRare"
        result = build_owned_weapons({
            "Pistols": [{
                "ItemId": "test-laetum",
                "ItemType": weapon_type,
                "Configs": [{"Upgrades": ["test-riven"]}],
            }],
            "Upgrades": [{
                "ItemId": "test-riven",
                "ItemType": riven_type,
                "UpgradeFingerprint": json.dumps({
                    "lvl": 8,
                    "buffs": [{
                        "Tag": "WeaponCorrosiveDamageMod",
                        "Value": RIVEN_MAXIMUM,
                    }],
                    "curses": [],
                }),
            }],
            "RawUpgrades": [],
        }, game_data_override={
            "weapons": {weapon_type: {"n": "Laetum", "z": "奏凯", "om": 1.2}},
            "mods": {},
            "rivenTags": self.official_riven_tags(),
        })

        config = result[0]["cfg"][0]
        self.assertTrue(config["exact"])
        self.assertEqual(config["u"], [])
        self.assertAlmostEqual(config["r"]["elements"]["corrosive"], 1.782)


if __name__ == "__main__":
    unittest.main()
