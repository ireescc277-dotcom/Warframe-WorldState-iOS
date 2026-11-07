import SwiftUI

public struct CountdownView: View {
    public let targetDate: Date?
    public var prefix: String = ""
    public var showSeconds: Bool = true
    
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(targetDate: Date?, prefix: String = "", showSeconds: Bool = true) {
        self.targetDate = targetDate
        self.prefix = prefix
        self.showSeconds = showSeconds
    }
    
    public var body: some View {
        let (text, color) = formatCountdown(target: targetDate, now: vm.currentTime)
        
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
            
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private func formatCountdown(target: Date?, now: Date) -> (String, Color) {
        guard let target = target else {
            return ("无到期时间", WFTheme.textMuted)
        }
        
        let diff = target.timeIntervalSince(now)
        if diff <= 0 {
            let past = abs(Int(diff))
            let m = past / 60
            if m < 60 {
                return ("已结束 (\(m)分钟前)", WFTheme.red)
            } else {
                let h = m / 60
                return ("已结束 (\(h)小时前)", WFTheme.red)
            }
        }
        
        let totalSeconds = Int(diff)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        let timeString: String
        if days > 0 {
            timeString = String(format: "%d天 %02d:%02d:%02d", days, hours, minutes, seconds)
        } else if showSeconds {
            timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            timeString = String(format: "%02d:%02d", hours, minutes)
        }
        
        let fullText = prefix.isEmpty ? timeString : "\(prefix) \(timeString)"
        
        if diff <= 3600 { // less than 1 hour
            return (fullText, WFTheme.gold)
        } else {
            return (fullText, WFTheme.green)
        }
    }
}
