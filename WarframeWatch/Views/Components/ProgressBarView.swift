import SwiftUI

public struct ProgressBarView: View {
    public let progress: Double // 0.0 to 100.0
    public var label: String? = nil
    public var tintGradient: LinearGradient = WFTheme.cyanGreenGradient
    public var height: CGFloat = 6
    
    public init(
        progress: Double,
        label: String? = nil,
        tintGradient: LinearGradient = WFTheme.cyanGreenGradient,
        height: CGFloat = 6
    ) {
        self.progress = max(0.0, min(100.0, progress))
        self.label = label
        self.tintGradient = tintGradient
        self.height = height
    }
    
    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(WFTheme.bgPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: height / 2)
                                .stroke(WFTheme.border, lineWidth: 1)
                        )
                    
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(tintGradient)
                        .frame(width: max(0, geo.size.width * CGFloat(progress / 100.0)))
                }
            }
            .frame(height: height)
            
            if let label = label {
                HStack {
                    Text(label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                    
                    Spacer()
                    
                    Text(String(format: "%.1f%%", progress))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(WFTheme.textSecondary)
                }
            }
        }
    }
}

/// Dual-sided tug of war progress bar for Invasions
public struct DuelProgressBarView: View {
    public let count: Int
    public let goal: Int
    public let attackerFaction: String
    public let defenderFaction: String
    
    public init(count: Int, goal: Int, attackerFaction: String, defenderFaction: String) {
        self.count = count
        self.goal = goal <= 0 ? 40000 : goal
        self.attackerFaction = attackerFaction
        self.defenderFaction = defenderFaction
    }
    
    public var body: some View {
        let progress = Double(abs(count)) / Double(goal)
        let clamped = max(0.0, min(1.0, progress))
        let attackerIsWinning = count < 0
        
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: attackerIsWinning ? .trailing : .leading) {
                    // Base background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "0C141C"))
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(attackerIsWinning ? WFTheme.cyan : WFTheme.gold)
                        .frame(width: geo.size.width * CGFloat(clamped))
                }
            }
            .frame(height: 6)
            
            HStack {
                Text(attackerFaction)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WFTheme.cyan)
                
                Spacer()
                
                Text(String(format: "%.1f%%", clamped * 100.0))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(WFTheme.textSecondary)
                
                Spacer()
                
                Text(defenderFaction)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WFTheme.gold)
            }
        }
    }
}
