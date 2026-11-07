import SwiftUI

public struct DiffListView: View {
    public let diffs: [DiffGroup]
    
    public init(diffs: [DiffGroup]) {
        self.diffs = diffs
    }
    
    public var body: some View {
        if diffs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundColor(WFTheme.green)
                
                Text("本次快照无条目变动")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WFTheme.textPrimary)
                
                Text("与上一份数据相比，所有任务与数值保持稳定。")
                    .font(.system(size: 12))
                    .foregroundColor(WFTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(diffs) { group in
                    WFCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TagView(group.groupName, style: .gold)
                                
                                Spacer()
                                
                                Text("\(group.totalChanges) 项变更")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(WFTheme.textSecondary)
                            }
                            
                            // Added (+)
                            ForEach(group.added, id: \.self) { item in
                                HStack(spacing: 6) {
                                    Text("+")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(WFTheme.green)
                                    Text(item)
                                        .font(.system(size: 12))
                                        .foregroundColor(WFTheme.textPrimary)
                                }
                            }
                            
                            // Removed (-)
                            ForEach(group.removed, id: \.self) { item in
                                HStack(spacing: 6) {
                                    Text("−")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(WFTheme.red)
                                    Text(item)
                                        .font(.system(size: 12))
                                        .foregroundColor(WFTheme.textSecondary)
                                        .strikethrough()
                                }
                            }
                            
                            // Changed (~)
                            ForEach(group.changed) { change in
                                HStack(spacing: 6) {
                                    Text("~")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(WFTheme.gold)
                                    
                                    Text(change.label)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(WFTheme.textPrimary)
                                    
                                    Spacer()
                                    
                                    Text("\(change.fromValue) → \(change.toValue)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(WFTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
