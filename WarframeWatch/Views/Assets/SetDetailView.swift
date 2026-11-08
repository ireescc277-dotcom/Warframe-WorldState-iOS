import SwiftUI

/// 单套详情：四个部件各值多少、整卖还是拆卖、哪张遗物能出。
///
/// 这里只放「能改变一个动作」的信息：值不值得拆、缺的那件在哪。
/// 历史价格、走势这类东西没有数据支撑，不编。
public struct SetDetailView: View {
    public let item: PrimeSet
    @Environment(\.dismiss) private var dismiss

    public init(set value: PrimeSet) {
        self.item = value
    }

    public var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: WFUI.s4) {
                    title
                    compareCard
                    partsCard
                    if !item.relics.isEmpty { relicCard }
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(WFTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(WFUI.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.zh)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(WFTheme.textPrimary)
            Text(statusLine)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
        .padding(.trailing, 44)
    }

    private var statusLine: String {
        if item.isOwned {
            let spare = item.parts.reduce(0) { $0 + $1.n }
            return "\(item.cat) · 已成套 · 手上还有 \(spare) 件散件"
        }
        if item.isReady { return "\(item.cat) · 部件齐全，还没造" }
        return "\(item.cat) · 缺 \(item.missing) 件：\(missingLabels)"
    }

    private var missingLabels: String {
        item.parts.filter { !$0.owned }.map(\.l).joined(separator: "、")
    }

    // MARK: - 整卖 vs 拆卖

    private var compareCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                priceCell("整套卖", item.setPrice, highlight: item.splitGain <= 0)
                Rectangle().fill(WFUI.hairline).frame(width: 0.5, height: 40)
                priceCell("拆开卖", item.partsValue, highlight: item.splitGain > 0)
            }
            .padding(.vertical, 15)

            if item.setPrice > 0 && item.partsValue > 0 {
                WFHairline()
                HStack(spacing: 6) {
                    Image(systemName: item.splitGain > 0 ? "scissors" : "shippingbox")
                        .font(.system(size: 11))
                    Text(verdict)
                        .font(.system(size: 12))
                }
                .foregroundColor(item.splitGain > 0 ? WFTheme.cyan : WFTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private var verdict: String {
        if item.splitGain == 0 { return "整卖和拆卖差不多" }
        if item.splitGain > 0 { return "拆开卖多 \(item.splitGain) p" }
        return "整卖更划算，多 \(-item.splitGain) p"
    }

    private func priceCell(_ label: String, _ value: Int, highlight: Bool) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value > 0 ? "\(value)" : "—")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(highlight ? WFTheme.gold : WFTheme.textSecondary)
                if value > 0 {
                    Text("p")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WFTheme.textMuted)
                }
            }
            Text(label)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 部件

    private var partsCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("部件", trailing: "持有 · 市价 · Ducats")
            WFSurface {
                ForEach(Array(item.parts.enumerated()), id: \.element.id) { index, part in
                    partRow(part, isLast: index == item.parts.count - 1)
                }
            }
        }
    }

    private func partRow(_ part: PrimeSet.Part, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: WFUI.s3) {
                Image(systemName: part.owned ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 13))
                    .foregroundColor(part.owned ? WFTheme.green : WFTheme.textMuted.opacity(0.6))
                    .frame(width: 16)

                Text(part.l)
                    .font(.wfBody)
                    .foregroundColor(part.owned ? WFTheme.textPrimary : WFTheme.textSecondary)

                Spacer(minLength: WFUI.s2)

                Text(part.n > 0 ? "×\(part.n)" : "—")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(part.n > 1 ? WFTheme.cyan : WFTheme.textSecondary)
                    .frame(minWidth: 32, alignment: .trailing)

                Text(part.p > 0 ? "\(part.p) p" : "—")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(part.p > 0 ? WFTheme.gold : WFTheme.textMuted)
                    .frame(minWidth: 46, alignment: .trailing)

                Text(part.d > 0 ? "\(part.d)" : "—")
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WFTheme.textMuted)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !isLast { WFHairline().padding(.leading, 44) }
        }
    }

    // MARK: - 遗物

    private var relicCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("能出的遗物", trailing: "\(item.relics.count) 张")
            WFSurface {
                FlowingText(items: item.relics)
                    .padding(14)
            }
        }
    }
}

/// 遗物代号长短不一，用自动换行的流式布局，比折成两行列表省一半高度。
private struct FlowingText: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 11.5))
                            .foregroundColor(WFTheme.cyan)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(WFTheme.cyan.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 每行最多 4 个，够用且不会在窄屏上挤爆。
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 4).map {
            Array(items[$0 ..< min($0 + 4, items.count)])
        }
    }
}
