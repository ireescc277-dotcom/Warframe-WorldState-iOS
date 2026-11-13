import Combine
import CryptoKit
import Foundation

/// 背包资产的离线快照。
///
/// 数据由 `scripts/build_app_inventory.py` 生成：背包来自 AlecaFrame 的
/// `lastData.dat`（静态 AES key 本地解密，不联网、不读进程内存），价格来自
/// warframe.market v2，Ducats 来自 DE 的 Components 表。
///
/// 价格口径只用**在线卖家的最低价**。market 上有人挂 1p 钓鱼单，
/// 用「全部卖单最低价」会把 Lavos Prime 套装算成 1p。
public struct InventoryData: Decodable {
    public let builtAt: String
    public let source: Source?
    public let marketAt: String?
    public let profile: Profile
    public let totals: Totals
    public let aya: AyaShop
    public let sets: [PrimeSet]
    public let relics: [RelicRow]
    public let ownedWeapons: [OwnedWeapon]
    /// Owned Warframe instances retain their own A/B/C configurations.  This
    /// is deliberately not collapsed into an app-wide "ability strength".
    public let ownedWarframes: [OwnedWarframe]
    /// Companion bodies retain their own A/B/C Mod and Arcane configuration.
    /// They are separate from `ownedWeapons`: a companion weapon is still a
    /// weapon, whereas the Sentinel/Pet itself is a configuration body.
    public let ownedCompanions: [OwnedEquipment]
    /// Beast companion weapons are stored by DE in a different account source
    /// from Sentinel weapons; keep their imported configs separate instead of
    /// substituting a same-name weapon from another category.
    public let ownedCompanionWeapons: [OwnedEquipment]
    /// Archwing bodies retain A/B/C configuration independently of Archguns
    /// and Arch-melee weapons.
    public let ownedArchwings: [OwnedEquipment]
    /// Source-ordered entries from DE's account-level gear wheel.  This is
    /// not inferred to belong to a particular normal Arsenal preset.
    public let equippedGear: [EquippedGearItem]
    /// DE preset families reference concrete items above by opaque id.  A
    /// snapshot can mark more than one family as active, so `active` is
    /// source evidence, not a claim that we inferred one global preset.
    public let loadouts: [Loadout]

    private enum CodingKeys: String, CodingKey {
        case builtAt, source, marketAt, profile, totals, aya, sets, relics, ownedWeapons
        case ownedWarframes, ownedCompanions, ownedCompanionWeapons, ownedArchwings, equippedGear, loadouts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Old bundled samples intentionally remain readable.  Remote data uses
        // InventoryManifest for identity; builtAt is only legacy display data.
        builtAt = try c.decodeIfPresent(String.self, forKey: .builtAt)
            ?? "1970-01-01T00:00:00Z"
        source = try c.decodeIfPresent(Source.self, forKey: .source)
        marketAt = try c.decodeIfPresent(String.self, forKey: .marketAt)
        profile = try c.decode(Profile.self, forKey: .profile)
        totals = try c.decode(Totals.self, forKey: .totals)
        aya = try c.decode(AyaShop.self, forKey: .aya)
        sets = try c.decodeIfPresent([PrimeSet].self, forKey: .sets) ?? []
        relics = try c.decodeIfPresent([RelicRow].self, forKey: .relics) ?? []
        ownedWeapons = try c.decodeIfPresent([OwnedWeapon].self, forKey: .ownedWeapons) ?? []
        ownedWarframes = try c.decodeIfPresent([OwnedWarframe].self, forKey: .ownedWarframes) ?? []
        ownedCompanions = try c.decodeIfPresent([OwnedEquipment].self, forKey: .ownedCompanions) ?? []
        ownedCompanionWeapons = try c.decodeIfPresent([OwnedEquipment].self, forKey: .ownedCompanionWeapons) ?? []
        ownedArchwings = try c.decodeIfPresent([OwnedEquipment].self, forKey: .ownedArchwings) ?? []
        equippedGear = try c.decodeIfPresent([EquippedGearItem].self, forKey: .equippedGear) ?? []
        loadouts = try c.decodeIfPresent([Loadout].self, forKey: .loadouts) ?? []
    }

    /// Provenance of the account snapshot consumed by this payload.  The
    /// value is a SHA-256, never a DE account/item identifier.
    public struct Source: Decodable, Hashable {
        public let accountHash: String
        public let accountSync: String?
    }

    public struct Profile: Decodable {
        public let mr: Int
        public let plat: Int
        public let credits: Int
        public let sync: String?
    }

    public struct Totals: Decodable {
        public let setsOwned: Int
        public let setsReady: Int
        public let setsClose: Int
        public let setsAll: Int
        /// Direct sum of every owned Prime component's listed unit price.
        /// It never applies a crafting-reserve rule.
        public let allPlat: Int?
        /// Coverage behind `allPlat`; an unquoted part is not pretended to be
        /// a zero-plat item.
        public let primePartUnits: Int?
        public let pricedPrimePartUnits: Int?
        /// Market value after retaining one component for each uncrafted set.
        /// This is only a surplus-selling comparison, not the total.
        public let loosePlat: Int
        /// Every owned Prime component's exchange value.  This is the number
        /// AlecaFrame shows when no crafting reserve is applied.
        public let allDucats: Int?
        /// Exchange value after retaining one of each part for uncrafted sets.
        /// Kept for backwards-compatible payload decoding and for comparison.
        public let looseDucats: Int
        public let relicKinds: Int
        public let relicUnits: Int
        public let mods: Int
    }

    /// One owned weapon *instance*.  Same-name weapons deliberately stay as
    /// separate rows because Kuva/Tenet progenitor values and A/B/C configs
    /// are per instance, not per public weapon definition.
    public struct OwnedWeapon: Decodable, Identifiable, Hashable {
        public let id: String
        /// Calculator's canonical English weapon name, nil when its static
        /// data is not yet included in this app build.
        public let calcName: String?
        public let z: String
        public let category: String
        public let inventoryCategory: String
        public let progenitorElements: [String: Double]
        /// Per-unlocked-tier choices from the instance's DE SkillTree string.
        /// The calculator maps their positions to its own tier IDs after the
        /// weapon definition has loaded.
        public let incarnonChoices: [Int]
        public let configs: [Config]

        private enum CodingKeys: String, CodingKey {
            case id, n, z, c, k, p, inc, cfg
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            calcName = try c.decodeIfPresent(String.self, forKey: .n)
            z = try c.decode(String.self, forKey: .z)
            category = try c.decodeIfPresent(String.self, forKey: .c) ?? "Unknown"
            inventoryCategory = try c.decodeIfPresent(String.self, forKey: .k) ?? "Unknown"
            progenitorElements = try c.decodeIfPresent([String: Double].self, forKey: .p) ?? [:]
            incarnonChoices = try c.decodeIfPresent([Int].self, forKey: .inc) ?? []
            configs = try c.decodeIfPresent([Config].self, forKey: .cfg) ?? []
        }

        public var isCalculable: Bool { calcName != nil }

        public var categoryLabel: String {
            switch category {
            case "Primary": return "主武器"
            case "Secondary": return "副武器"
            case "Melee": return "近战"
            case "Archgun": return "Archwing 枪械"
            case "Archmelee": return "Archwing 近战"
            case "Companion": return "同伴武器"
            case "Operator": return "指挥官武器"
            default: return category
            }
        }

        public struct Config: Decodable, Hashable, Identifiable {
            public let label: String
            /// DamageKit's stable slots: 0...8, melee stance 9, Arcane 10.
            public let slots: [String?]
            /// Actual source ranks for the imported slots. A non-nil
            /// `actionScale` is emitted only when the snapshot builder proved
            /// the card's complete DamageKit action scales linearly at that
            /// rank; it is never a client-side "assume max" fallback.
            public let slotMetadata: [SlotMetadata?]
            /// Equipped upgrades the source snapshot did identify but that
            /// this app cannot yet feed into DamageKit exactly. They stay
            /// visible with their real slot/rank instead of disappearing as
            /// an empty slot or being treated as a full-rank card.
            public let unresolvedUpgrades: [UnresolvedUpgrade]
            /// Equipped cards whose *entire source rank table* is proven to
            /// affect something outside the hit/DOT number calculated here
            /// (for example, weapon noise, range, or an orb drop chance).
            /// They remain part of the visible imported configuration, but do
            /// not make an otherwise exact damage result appear incomplete.
            public let nonDamageUpgrades: [NonDamageUpgrade]
            public let riven: ImportedRiven?
            public let rivenSlot: Int?
            /// False means at least one source slot could not be brought into
            /// the calculator exactly.  `issues` says whether the source
            /// omitted a rank, referenced a missing item, or used an unmapped
            /// upgrade; it is not a generic "max rank" warning.
            public let isExactImport: Bool
            public let issues: [String]

            public var id: String { label }
            public var normalizedSlots: [String?] {
                Array(slots.prefix(11)) + Array(repeating: nil, count: max(0, 11 - slots.count))
            }

            public var normalizedSlotMetadata: [SlotMetadata?] {
                Array(slotMetadata.prefix(11))
                    + Array(repeating: nil, count: max(0, 11 - slotMetadata.count))
            }

            public var normalizedSlotActionScales: [Double?] {
                normalizedSlotMetadata.map { $0?.actionScale }
            }

            /// A concrete lower-ranked condition card can retain its ordinary
            /// final cap but grant less per gameplay input (for example, per
            /// ability cast).  This value is independently source-proven by
            /// the payload builder; it must never be inferred from rank.
            public var normalizedSlotConditionalStepScales: [Double?] {
                normalizedSlotMetadata.map { $0?.conditionalStepScale }
            }

            public func metadata(at slot: Int) -> SlotMetadata? {
                guard normalizedSlotMetadata.indices.contains(slot) else { return nil }
                return normalizedSlotMetadata[slot]
            }

            private enum CodingKeys: String, CodingKey {
                case l, s, sm, u, nd, r, rs, exact, issues
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                label = try c.decodeIfPresent(String.self, forKey: .l) ?? "A"
                slots = try c.decodeIfPresent([String?].self, forKey: .s) ?? []
                slotMetadata = try c.decodeIfPresent([SlotMetadata?].self, forKey: .sm) ?? []
                unresolvedUpgrades = try c.decodeIfPresent([UnresolvedUpgrade].self, forKey: .u) ?? []
                nonDamageUpgrades = try c.decodeIfPresent([NonDamageUpgrade].self, forKey: .nd) ?? []
                riven = try c.decodeIfPresent(ImportedRiven.self, forKey: .r)
                rivenSlot = try c.decodeIfPresent(Int.self, forKey: .rs)
                isExactImport = try c.decodeIfPresent(Bool.self, forKey: .exact) ?? true
                issues = try c.decodeIfPresent([String].self, forKey: .issues) ?? []
            }

            public struct SlotMetadata: Decodable, Hashable {
                public let rank: Int?
                public let maxRank: Int?
                public let actionScale: Double?
                public let conditionalStepScale: Double?

                private enum CodingKeys: String, CodingKey { case r, m, a, c }

                public init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    rank = try c.decodeIfPresent(Int.self, forKey: .r)
                    maxRank = try c.decodeIfPresent(Int.self, forKey: .m)
                    actionScale = try c.decodeIfPresent(Double.self, forKey: .a)
                    conditionalStepScale = try c.decodeIfPresent(Double.self, forKey: .c)
                }

                public var rankLabel: String? {
                    switch (rank, maxRank) {
                    case let (.some(rank), .some(maximum)):
                        return "等级 \(rank)/\(maximum)"
                    case let (.some(rank), .none):
                        return "等级 \(rank)"
                    default:
                        return nil
                    }
                }
            }

            public struct UnresolvedUpgrade: Decodable, Hashable, Identifiable {
                /// DamageKit slot if one exists; otherwise the source slot.
                public let slot: Int
                public let name: String
                public let rank: Int?
                public let maxRank: Int?
                public let reason: String

                private enum CodingKeys: String, CodingKey { case s, n, r, m, why }

                public init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    slot = try c.decodeIfPresent(Int.self, forKey: .s) ?? 0
                    name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未命名升级"
                    rank = try c.decodeIfPresent(Int.self, forKey: .r)
                    maxRank = try c.decodeIfPresent(Int.self, forKey: .m)
                    reason = try c.decodeIfPresent(String.self, forKey: .why) ?? "尚未接入伤害公式"
                }

                public var id: String { "\(slot):\(name):\(reason)" }

                public var rankLabel: String? {
                    switch (rank, maxRank) {
                    case let (.some(rank), .some(maximum)):
                        return "等级 \(rank)/\(maximum)"
                    case let (.some(rank), .none):
                        return "等级 \(rank)"
                    default:
                        return nil
                    }
                }
            }

            public struct NonDamageUpgrade: Decodable, Hashable, Identifiable {
                /// DamageKit slot if one exists; otherwise the source slot.
                public let slot: Int
                public let name: String
                public let rank: Int?
                public let maxRank: Int?
                /// Source-proven explanation of why the equipped card does
                /// not change this calculator's hit/DOT number.
                public let reason: String

                private enum CodingKeys: String, CodingKey { case s, n, r, m, why }

                public init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    slot = try c.decodeIfPresent(Int.self, forKey: .s) ?? 0
                    name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未命名升级"
                    rank = try c.decodeIfPresent(Int.self, forKey: .r)
                    maxRank = try c.decodeIfPresent(Int.self, forKey: .m)
                    reason = try c.decodeIfPresent(String.self, forKey: .why) ?? "不直接改变本次伤害数值"
                }

                public var id: String { "\(slot):\(name):\(reason)" }

                public var rankLabel: String? {
                    switch (rank, maxRank) {
                    case let (.some(rank), .some(maximum)):
                        return "等级 \(rank)/\(maximum)"
                    case let (.some(rank), .none):
                        return "等级 \(rank)"
                    default:
                        return nil
                    }
                }
            }
        }

        /// Resolved numerical purple-card effects.  Values use DamageKit's
        /// decimal units (0.9 = +90%); raw Riven instance identifiers and
        /// fingerprints never leave the account-snapshot import boundary.
        public struct ImportedRiven: Decodable, Hashable {
            public let name: String
            public let damage: Double?
            public let multishot: Double?
            public let critChance: Double?
            public let critDamage: Double?
            public let statusChance: Double?
            public let statusDuration: Double?
            public let fireRate: Double?
            public let reloadSpeed: Double?
            public let magazineSize: Double?
            public let meleeComboEfficiency: Double?
            public let faction: Double?
            public let factionBonuses: [String: Double]?
            public let elements: [String: Double]?
            public let physical: [String: Double]?
            /// Raw Riven terms retained for inspection when DamageKit has no
            /// corresponding damage rule.  They are deliberately visible,
            /// rather than guessed as another stat or silently discarded.
            public let unresolved: [UnresolvedEffect]?
            /// Real source-card terms retained for audit that do not enter the
            /// current already-landed-hit simulation (for example zoom).
            public let displayOnly: [DisplayOnlyEffect]?

            public struct UnresolvedEffect: Decodable, Hashable, Identifiable {
                public let tag: String
                public let label: String

                public var id: String { tag }
            }

            public struct DisplayOnlyEffect: Decodable, Hashable, Identifiable {
                public let tag: String
                public let label: String
                /// Decimal display unit: `0.45` means `+45%`.
                public let value: Double

                public var id: String { tag }
            }
        }
    }

    /// One owned Warframe instance and the source data that determines the
    /// strength of its abilities.  `configs` retains actual equipped upgrades
    /// (including non-strength cards) so a user can audit the selected build
    /// instead of trusting a hidden final-stat field.
    public struct OwnedWarframe: Decodable, Identifiable, Hashable {
        public let id: String
        public let z: String
        public let abilities: [Ability]
        public let configs: [Config]
        /// Shards live on the Warframe instance, not on a weapon config.
        public let shards: [Shard]

        private enum CodingKeys: String, CodingKey { case id, z, a, cfg, sh }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            z = try c.decodeIfPresent(String.self, forKey: .z) ?? "未命名战甲"
            abilities = try c.decodeIfPresent([Ability].self, forKey: .a) ?? []
            configs = try c.decodeIfPresent([Config].self, forKey: .cfg) ?? []
            shards = try c.decodeIfPresent([Shard].self, forKey: .sh) ?? []
        }

        public func config(at index: Int) -> Config? {
            guard configs.indices.contains(index) else { return nil }
            return configs[index]
        }

        public struct Ability: Decodable, Hashable, Identifiable {
            /// 1...4 for native abilities.  The actual formula owner may use
            /// this to apply a card such as Precision Intensify.
            public let ordinal: Int
            public let name: String
            public var id: Int { ordinal }

            private enum CodingKeys: String, CodingKey { case o, n }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                ordinal = try c.decodeIfPresent(Int.self, forKey: .o) ?? 0
                name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未命名技能"
            }
        }

        public struct Config: Decodable, Hashable, Identifiable {
            public let label: String
            public let upgrades: [Upgrade]
            public let helminth: HelminthAbility?
            public let isExactImport: Bool
            public let issues: [String]
            public var id: String { label }

            private enum CodingKeys: String, CodingKey { case l, u, h, exact, issues }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                label = try c.decodeIfPresent(String.self, forKey: .l) ?? "A"
                upgrades = try c.decodeIfPresent([Upgrade].self, forKey: .u) ?? []
                helminth = try c.decodeIfPresent(HelminthAbility.self, forKey: .h)
                isExactImport = try c.decodeIfPresent(Bool.self, forKey: .exact) ?? true
                issues = try c.decodeIfPresent([String].self, forKey: .issues) ?? []
            }
        }

        public struct Upgrade: Decodable, Hashable, Identifiable {
            public let slot: Int
            public let name: String
            public let rank: Int?
            public let maxRank: Int?
            public let kind: String
            /// Only terms with an exact unconditional formula are in this
            /// list.  Conditional / stateful text remains in `strengthReview`
            /// until the corresponding game state is modelled explicitly.
            public let strengthTerms: [StrengthTerm]
            public let strengthReview: [String]
            /// Exact coefficient printed by the installed rank of a
            /// strength-scaled weapon-buff augment.  `1` is its max-rank
            /// action-table value; a lower rank is deliberately retained as
            /// its own value rather than silently treated as max rank.
            public let weaponBuffScale: Double?
            public var id: Int { slot }

            private enum CodingKeys: String, CodingKey { case s, n, r, m, k, st, sr, wb }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                slot = try c.decodeIfPresent(Int.self, forKey: .s) ?? -1
                name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未识别升级"
                rank = try c.decodeIfPresent(Int.self, forKey: .r)
                maxRank = try c.decodeIfPresent(Int.self, forKey: .m)
                kind = try c.decodeIfPresent(String.self, forKey: .k) ?? "Mod"
                strengthTerms = try c.decodeIfPresent([StrengthTerm].self, forKey: .st) ?? []
                strengthReview = try c.decodeIfPresent([String].self, forKey: .sr) ?? []
                weaponBuffScale = try c.decodeIfPresent(Double.self, forKey: .wb)
            }

            public var rankLabel: String {
                guard let rank else { return "等级未确认" }
                guard let maxRank else { return "等级 \(rank)" }
                return "等级 \(rank)/\(maxRank)"
            }
        }

        public struct StrengthTerm: Decodable, Hashable, Identifiable {
            public let label: String
            /// Decimal bonus: 0.30 means +30% Ability Strength.
            public let value: Double
            /// `base` or `ability4`; values are never inferred from display
            /// strings in Swift.
            public let kind: String
            public var id: String { "\(kind)-\(label)-\(value)" }

            private enum CodingKeys: String, CodingKey { case l, v, k }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                label = try c.decodeIfPresent(String.self, forKey: .l) ?? "技能强度"
                value = try c.decodeIfPresent(Double.self, forKey: .v) ?? 0
                kind = try c.decodeIfPresent(String.self, forKey: .k) ?? "base"
            }
        }

        public struct HelminthAbility: Decodable, Hashable {
            /// DE records the replaced native slot as zero-based; keep that
            /// source convention and add one only when presenting it.
            public let replacedIndex: Int?
            public let name: String

            private enum CodingKeys: String, CodingKey { case o, n }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                replacedIndex = try c.decodeIfPresent(Int.self, forKey: .o)
                name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未识别的 Helminth 技能"
            }
        }

        public struct Shard: Decodable, Hashable, Identifiable {
            public let slot: Int
            public let name: String
            /// DamageKit's existing shard definition, when this shard affects
            /// weapon damage.  Ability-strength shards intentionally use the
            /// separate `abilityStrength` field instead.
            public let damageKitName: String?
            public let abilityStrength: Double?
            public let isTauforged: Bool
            public var id: Int { slot }

            private enum CodingKeys: String, CodingKey { case s, n, dk, `as`, tau }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                slot = try c.decodeIfPresent(Int.self, forKey: .s) ?? -1
                name = try c.decodeIfPresent(String.self, forKey: .n) ?? "执政官石"
                damageKitName = try c.decodeIfPresent(String.self, forKey: .dk)
                abilityStrength = try c.decodeIfPresent(Double.self, forKey: .as)
                isTauforged = try c.decodeIfPresent(Bool.self, forKey: .tau) ?? false
            }
        }
    }

    /// An owned companion or Archwing body.  It has a true account instance
    /// and A/B/C build, but is intentionally not fed to the weapon calculator
    /// as if it were a normal gun.
    public struct OwnedEquipment: Decodable, Identifiable, Hashable {
        public let id: String
        public let z: String
        /// Snapshot category, e.g. `Sentinels`, `KubrowPets`, `MoaPets`, or
        /// `SpaceSuits`.  It is static equipment taxonomy, not a private ID.
        public let inventoryCategory: String
        public let configs: [Config]

        private enum CodingKeys: String, CodingKey { case id, z, k, cfg }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            z = try c.decodeIfPresent(String.self, forKey: .z) ?? "未命名装备"
            inventoryCategory = try c.decodeIfPresent(String.self, forKey: .k) ?? "Unknown"
            configs = try c.decodeIfPresent([Config].self, forKey: .cfg) ?? []
        }

        public func config(at index: Int) -> Config? {
            guard configs.indices.contains(index) else { return nil }
            return configs[index]
        }

        public var categoryLabel: String {
            switch inventoryCategory {
            case "Sentinels": return "守护"
            case "KubrowPets": return "库狛"
            case "MoaPets": return "恐鸟"
            case "CompanionWeapons": return "同伴武器"
            case "SpaceSuits": return "Archwing"
            default: return inventoryCategory
            }
        }

        public struct Config: Decodable, Hashable, Identifiable {
            public let label: String
            public let upgrades: [Upgrade]
            public let isExactImport: Bool
            public let issues: [String]
            public var id: String { label }

            private enum CodingKeys: String, CodingKey { case l, u, exact, issues }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                label = try c.decodeIfPresent(String.self, forKey: .l) ?? "A"
                upgrades = try c.decodeIfPresent([Upgrade].self, forKey: .u) ?? []
                isExactImport = try c.decodeIfPresent(Bool.self, forKey: .exact) ?? true
                issues = try c.decodeIfPresent([String].self, forKey: .issues) ?? []
            }
        }

        public struct Upgrade: Decodable, Hashable, Identifiable {
            public let slot: Int
            public let name: String
            public let rank: Int?
            public let maxRank: Int?
            public let kind: String
            public var id: Int { slot }

            private enum CodingKeys: String, CodingKey { case s, n, r, m, k }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                slot = try c.decodeIfPresent(Int.self, forKey: .s) ?? -1
                name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未识别升级"
                rank = try c.decodeIfPresent(Int.self, forKey: .r)
                maxRank = try c.decodeIfPresent(Int.self, forKey: .m)
                kind = try c.decodeIfPresent(String.self, forKey: .k) ?? "Mod"
            }

            public var rankLabel: String {
                guard let rank else { return "等级未确认" }
                guard let maxRank else { return "等级 \(rank)" }
                return "等级 \(rank)/\(maxRank)"
            }
        }
    }

    /// One source-ordered account gear-wheel entry.  Quantity is optional:
    /// only a stack record in the snapshot can establish it, while equipment
    /// such as a deployer must not be presented as having one fabricated use.
    public struct EquippedGearItem: Decodable, Identifiable, Hashable {
        public let id: String
        public let slot: Int
        public let name: String
        public let count: Int?

        private enum CodingKeys: String, CodingKey { case id, s, n, c }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            slot = try c.decodeIfPresent(Int.self, forKey: .s) ?? -1
            name = try c.decodeIfPresent(String.self, forKey: .n) ?? "未命名物品"
            count = try c.decodeIfPresent(Int.self, forKey: .c)
        }
    }

    /// A DE Arsenal preset family.  `normal`, `companion`, and `archwing`
    /// are distinct source lists; the UI may place them together for an
    /// Arsenal overview but must not claim an unrecorded cross-family link.
    public struct Loadout: Decodable, Identifiable, Hashable {
        public let id: String
        public let name: String
        public let kind: Kind
        public let isFavorite: Bool
        public let snapshotMarkedActive: Bool
        public let slots: [Slot]

        private enum CodingKeys: String, CodingKey { case id, n, t, fav, active, slots }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .n) ?? "配置"
            kind = try c.decodeIfPresent(Kind.self, forKey: .t) ?? .normal
            isFavorite = try c.decodeIfPresent(Bool.self, forKey: .fav) ?? false
            snapshotMarkedActive = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
            slots = try c.decodeIfPresent([Slot].self, forKey: .slots) ?? []
        }

        public enum Kind: String, Decodable, Hashable {
            case normal, companion, archwing

            public var label: String {
                switch self {
                case .normal: return "战甲与武器"
                case .companion: return "同伴"
                case .archwing: return "Archwing"
                }
            }
        }

        public func slot(_ role: Slot.Role) -> Slot? {
            slots.first { $0.role == role }
        }

        public struct Slot: Decodable, Hashable, Identifiable {
            public enum Role: String, Decodable, CaseIterable, Hashable {
                case warframe, primary, secondary, melee, heavy
                case companion, companionWeapon, archwing, archgun, archmelee

                public var label: String {
                    switch self {
                    case .warframe: return "战甲"
                    case .primary: return "主武器"
                    case .secondary: return "副武器"
                    case .melee: return "近战"
                    case .heavy: return "重型武器"
                    case .companion: return "同伴"
                    case .companionWeapon: return "同伴武器"
                    case .archwing: return "Archwing"
                    case .archgun: return "Archwing 枪械"
                    case .archmelee: return "Archwing 近战"
                    }
                }
            }

            public let role: Role
            public let itemID: String?
            public let displayName: String?
            public let configIndex: Int?
            public let isHidden: Bool
            /// A preset can reference an instance which is missing from the
            /// captured inventory rows.  It is a source condition, not an
            /// invitation to substitute a same-name item.
            public let sourceIssue: String?
            public var id: Role { role }

            private enum CodingKeys: String, CodingKey { case r, i, z, c, hide, x }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                role = try c.decode(Role.self, forKey: .r)
                itemID = try c.decodeIfPresent(String.self, forKey: .i)
                displayName = try c.decodeIfPresent(String.self, forKey: .z)
                configIndex = try c.decodeIfPresent(Int.self, forKey: .c)
                isHidden = try c.decodeIfPresent(Bool.self, forKey: .hide) ?? false
                sourceIssue = try c.decodeIfPresent(String.self, forKey: .x)
            }

            public var configLabel: String? {
                guard let configIndex, configIndex >= 0 else { return nil }
                return String(UnicodeScalar(65 + min(configIndex, 25)) ?? "?")
            }
        }
    }
}

public struct PrimeSet: Decodable, Identifiable {
    public let id: String
    public let zh: String
    public let cat: String
    public let i: String?           // Asset Catalog 里的缩略图名
    public let u: String?           // CDN 相对路径，本地没有图时兜底
    public let status: String        // owned / ready / missing
    public let have: Int
    public let total: Int
    public let parts: [Part]
    public let setPrice: Int
    public let partsValue: Int
    public let loose: Int            // 可卖散件的白金
    public let relics: [String]

    public struct Part: Decodable, Identifiable {
        public let l: String         // 中文部件名：蓝图 / 机体 / 头部神经光元 / 系统
        public let n: Int            // 持有数
        public let p: Int            // 市场价
        public let d: Int            // Ducats
        public var id: String { l }
        public var owned: Bool { n > 0 }
    }

    public var missing: Int { max(total - have, 0) }
    public var isOwned: Bool { status == "owned" }
    public var isReady: Bool { status == "ready" }

    /// 拆开卖零件比整套卖多的差额。正数说明拆卖更划算。
    public var splitGain: Int { partsValue - setPrice }
}

public struct RelicRow: Decodable, Identifiable {
    public let id: String            // 古纪 C10
    public let era: String
    public let code: String
    public let i: String?            // 同一纪元的遗物共用一张图
    public let u: String?
    public let st: [String: Int]     // I/E/F/R 四档持有
    public let n: Int                // 合计持有
    public let p: Int                // 市场价（按代号，不含精炼档）
    public let miss: Int             // 能出的、我还没有的套装数
    public let own: Int              // 能出的、我已有的套装数

    public var refine: [(String, Int)] {
        [("完整", st["I"] ?? 0), ("优良", st["E"] ?? 0),
         ("无瑕", st["F"] ?? 0), ("光辉", st["R"] ?? 0)]
    }
}

public struct AyaShop: Decodable {
    public let activation: String?
    public let expiry: String?
    public let location: String?
    public let items: [Item]

    public struct Item: Decodable, Identifiable {
        public let id: String
        public let i: String?
        public let u: String?
        public let p: Int
        public let owned: Bool
    }
}

// MARK: - 加载

/// The immutable pointer published by `scripts/wf_publish.py`.
///
/// The payload is uploaded and SHA-256 verified on the VPS *before* this
/// small manifest is atomically switched.  `publishedAt` therefore describes
/// the exact bytes named by `snapshotId`, not when an unrelated build ran.
public struct InventoryManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let snapshotId: String
    public let contentHash: String
    public let payload: String
    public let bytes: Int
    public let publishedAt: String
    public let sourceHash: String?
    public let sourceSync: String?
    public let sourceObservedAt: String?

    public var isValid: Bool {
        schemaVersion == 2
            && snapshotId == contentHash
            && InventoryStore.isSHA256(contentHash)
            && payload == "snapshots/\(contentHash).json"
            && (sourceHash == nil || InventoryStore.isSHA256(sourceHash ?? ""))
            && bytes >= 0
    }
}

enum InventorySnapshotError: LocalizedError {
    case invalidManifest
    case invalidPayloadURL
    case badHTTP(Int)
    case contentHashMismatch
    case badPayload

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "背包版本清单无效"
        case .invalidPayloadURL: return "背包版本清单中的数据地址无效"
        case .badHTTP(let code): return "背包同步请求返回 HTTP \(code)"
        case .contentHashMismatch: return "背包数据校验和与版本清单不一致"
        case .badPayload: return "背包数据无法解码"
        }
    }
}

struct InventoryStoredSnapshot {
    let data: InventoryData
    let manifest: InventoryManifest?
}

public enum InventoryStore {
    /// 远端 manifest 的位置。账号数据在 VPS 上，App 只负责验证、取和缓存。
    ///
    /// 地址不写在源码里：CI 打包后用 PlistBuddy 写进 Info.plist，
    /// 值来自仓库 secret。仓库公开也读不到这个链接。
    public static var remote: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: InventoryRemote.key) as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// First launch uses one coherent cached pair, otherwise the bundled
    /// sample.  There is deliberately no `max(builtAt)` comparison here: a
    /// timestamp can never select a payload from another snapshot.
    static func localized() -> InventoryStoredSnapshot? {
        cached() ?? bundled()
    }

    static func bundled() -> InventoryStoredSnapshot? {
        let urls: [URL?] = [
            Bundle.main.url(forResource: "InventoryData", withExtension: "json"),
            Bundle.main.url(forResource: "InventoryData", withExtension: "json",
                            subdirectory: "Resources"),
            Bundle.main.bundleURL.appendingPathComponent("InventoryData.json"),
        ]
        for case let url? in urls {
            if let data = try? Data(contentsOf: url), let doc = decode(data) {
                return InventoryStoredSnapshot(data: doc, manifest: nil)
            }
        }
        return nil
    }

    static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("InventorySnapshots", isDirectory: true)
    }

    static var cacheManifestURL: URL {
        cacheDirectory.appendingPathComponent("current-manifest.json")
    }

    static func payloadURL(snapshotID: String) -> URL? {
        guard isSHA256(snapshotID) else { return nil }
        return cacheDirectory.appendingPathComponent("\(snapshotID).json")
    }

    static func cached() -> InventoryStoredSnapshot? {
        guard let rawManifest = try? Data(contentsOf: cacheManifestURL),
              let manifest = try? JSONDecoder().decode(InventoryManifest.self, from: rawManifest),
              manifest.isValid,
              let payloadURL = payloadURL(snapshotID: manifest.snapshotId),
              let rawPayload = try? Data(contentsOf: payloadURL),
              sha256(rawPayload) == manifest.contentHash,
              let doc = decode(rawPayload)
        else { return nil }
        return InventoryStoredSnapshot(data: doc, manifest: manifest)
    }

    static func decode(_ data: Data) -> InventoryData? {
        do {
            return try JSONDecoder().decode(InventoryData.self, from: data)
        } catch {
            print("InventoryData 解码失败：\(error)")
            return nil
        }
    }

    static func persist(_ rawPayload: Data, manifest: InventoryManifest) throws {
        guard manifest.isValid, sha256(rawPayload) == manifest.contentHash,
              let payloadURL = payloadURL(snapshotID: manifest.snapshotId) else {
            throw InventorySnapshotError.contentHashMismatch
        }
        try FileManager.default.createDirectory(at: cacheDirectory,
                                                withIntermediateDirectories: true)
        // Immutable payload first, pointer second.  A termination between the
        // two leaves the old manifest usable; it can never point to partial
        // bytes from the new version.
        try rawPayload.write(to: payloadURL, options: .atomic)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: cacheManifestURL, options: .atomic)
    }

    static func payloadURL(for manifest: InventoryManifest, relativeTo remote: URL) -> URL? {
        guard manifest.isValid else { return nil }
        return URL(string: manifest.payload, relativeTo: remote)?.absoluteURL
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
        }
    }
}

/// 拿到新数据后，界面要跟着换，所以套一层可观察对象。
///
/// 类本身不是 `@MainActor`：`shared` 要在 View 的属性初始化器里访问，
/// 那里是同步的非隔离上下文。只有写 `@Published` 的 `refresh` 标了主线程。
public final class InventoryFeed: ObservableObject {
    public static let shared = InventoryFeed()

    @Published public private(set) var data: InventoryData?
    @Published public private(set) var manifest: InventoryManifest?
    @Published public private(set) var fetching = false
    @Published public private(set) var failed = false
    /// Local time when this device successfully verified and applied the
    /// current manifest/payload pair.  It is never presented as server time.
    @Published public private(set) var appliedAt: String?
    @Published public private(set) var lastError: String?

    private init() {
        if let local = InventoryStore.localized() {
            data = local.data
            manifest = local.manifest
        }
    }

    /// 拉 VPS 上的那一份。失败就继续用手里的，不清空。
    @MainActor
    public func refresh() async {
        guard let remote = InventoryStore.remote else { return }
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }

        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (rawManifest, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw InventorySnapshotError.badHTTP((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let candidate = try JSONDecoder().decode(InventoryManifest.self, from: rawManifest)
            guard candidate.isValid else { throw InventorySnapshotError.invalidManifest }

            // Same immutable content means exactly the same display version;
            // do not update a time label merely because the user pulled again.
            if let current = manifest,
               current.snapshotId == candidate.snapshotId,
               current.contentHash == candidate.contentHash {
                failed = false
                lastError = nil
                return
            }

            guard let payloadURL = InventoryStore.payloadURL(for: candidate, relativeTo: remote) else {
                throw InventorySnapshotError.invalidPayloadURL
            }
            var payloadRequest = URLRequest(url: payloadURL)
            payloadRequest.timeoutInterval = 20
            payloadRequest.cachePolicy = .reloadIgnoringLocalCacheData
            let (rawPayload, payloadResponse) = try await URLSession.shared.data(for: payloadRequest)
            guard let payloadHTTP = payloadResponse as? HTTPURLResponse,
                  payloadHTTP.statusCode == 200 else {
                throw InventorySnapshotError.badHTTP((payloadResponse as? HTTPURLResponse)?.statusCode ?? -1)
            }
            guard rawPayload.count == candidate.bytes,
                  InventoryStore.sha256(rawPayload) == candidate.contentHash else {
                throw InventorySnapshotError.contentHashMismatch
            }
            guard let doc = InventoryStore.decode(rawPayload) else {
                throw InventorySnapshotError.badPayload
            }
            if let sourceHash = candidate.sourceHash,
               doc.source?.accountHash != sourceHash {
                throw InventorySnapshotError.badPayload
            }
            try InventoryStore.persist(rawPayload, manifest: candidate)
            data = doc
            manifest = candidate
            appliedAt = Self.isoNow()
            failed = false
            lastError = nil
        } catch {
            failed = true
            lastError = error.localizedDescription
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// 部署时改这里。空的就只用内置快照。
public enum InventoryRemote {
    /// 这个地址由 CI 写进 Info.plist，源码里不出现。
    public static let key = "InventoryURL"
}

// MARK: - 格式化

public enum AssetFormat {
    public static func plat(_ value: Int) -> String {
        value >= 1000 ? grouped(value) : "\(value)"
    }

    public static func grouped(_ value: Int) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.groupingSeparator = ","
        return n.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// `2026-11-08T09:38:00Z` → `11-08 17:38`（本地时区）
    ///
    /// DE 的时间戳带毫秒（`...T18:00:00.000Z`），默认的 ISO8601 解析器不认，
    /// 所以带小数秒要再试一次，否则像「本期到 —」这种空值会静默混进界面。
    public static func stamp(_ iso: String?) -> String {
        guard let iso = iso else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        var date = parser.date(from: iso)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = parser.date(from: iso)
        }
        guard let parsed = date else { return "—" }
        let out = DateFormatter()
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: parsed)
    }
}
