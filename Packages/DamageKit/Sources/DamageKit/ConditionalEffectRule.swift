import Foundation

/// 一个可叠层 `WITH_COND` 的结算声明。
///
/// 网站的原始 Mod 数据只给出“满层数值”，不说明它是满层**总量**还是额外
/// 加成。例如 Galvanized Chamber 的 `2.3` 包含卡面固有的 `0.8`，而
/// Cascadia Flare 的 `4.8` 全部是额外伤害。把这个区别做成资源数据，避免
/// 在输入/解析路径里按 Mod 名称分支。
public struct ConditionalEffectRule: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        /// `WITH_COND` 是满层总值；先减去普通 action 中已应用的同名字段。
        case totalRelativeToStaticAction
        /// `WITH_COND` 是满层额外值；按当前层数线性取其一部分。
        case scaledConditionalValue
    }

    /// `base_per_status` 的语义不在原始 Mod JSON 中：同一个数值可能是常驻
    /// Condition Overload，也可能是要由击杀层数启用的 Gun CO。这个声明让
    /// 解析器按数据表处理，不在输入或公式路径里按 Mod 名称写分支。
    public struct PerStatusDamage: Codable, Sendable, Equatable {
        public enum Activation: String, Codable, Sendable {
            /// 装上 Mod 后，目标每一种已有状态立即生效（Condition Overload）。
            case always
            /// 由该 Mod 的击杀层数线性启用（Galvanized Aptitude / Savvy / Shot）。
            case conditionalStacks
        }

        public var activation: Activation
        /// 这些攻击段不获得此 Mod 的加成。当前原始武器数据用 `AoE` 标记
        /// 半径伤害段；直击段则照常生效。
        public var excludedShotTypes: [String]

        public init(activation: Activation, excludedShotTypes: [String] = []) {
            self.activation = activation
            self.excludedShotTypes = excludedShotTypes
        }
    }

    /// 规则对应的 Mod 显示名。仅用作数据表索引，不参与公式分支。
    public var mod: String
    public var maxStacks: Double
    public var mode: Mode
    /// 本条规则负责的 `WITH_COND` action 键。
    public var keys: [String]
    /// `base_per_status` 的层数与攻击段适用范围；没有该字段时，本规则只描述
    /// `WITH_COND` 的插值语义。
    public var perStatusDamage: PerStatusDamage?

    /// 是否需要在 UI 中向用户索取层数。常驻 CO 不需要层数输入；`WITH_COND`
    /// 与击杀叠层效果需要。
    public var requiresManualStackInput: Bool {
        !keys.isEmpty || perStatusDamage?.activation == .conditionalStacks
    }

    public init(mod: String, maxStacks: Double, mode: Mode, keys: [String],
                perStatusDamage: PerStatusDamage? = nil) {
        self.mod = mod
        self.maxStacks = maxStacks
        self.mode = mode
        self.keys = keys
        self.perStatusDamage = perStatusDamage
    }
}
