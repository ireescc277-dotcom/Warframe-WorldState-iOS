import SwiftUI

public struct NightwaveActsView: View {
    public let season: SeasonInfo
    
    @State private var completedActs: Set<String> = []
    private let dict = DictionaryService.shared
    
    public init(season: SeasonInfo) {
        self.season = season
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Season Header
            WFCard(isHighlighted: true) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            TagView("NIGHTWAVE", style: .purple, icon: "radio.fill")
                            
                            Text("午夜电波 第 \(season.Season ?? 0) 季")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(WFTheme.purple)
                        }
                        
                        if let tag = season.AffiliationTag {
                            Text("当前主题: \(dict.syndicate(tag))")
                                .font(.system(size: 11))
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                    
                    Spacer()
                    
                    CountdownView(targetDate: season.Expiry?.date, prefix: "赛季剩余")
                }
            }
            
            // Challenges List
            if let challenges = season.ActiveChallenges {
                VStack(spacing: 8) {
                    ForEach(challenges) { ch in
                        actRow(ch: ch)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func actRow(ch: SeasonChallenge) -> some View {
        let isDone = completedActs.contains(ch.id)
        let actName = dict.humanize(ch.Challenge.split(separator: "/").last.map(String.init) ?? ch.Challenge)
        
        WFCard {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring()) {
                        if isDone {
                            completedActs.remove(ch.id)
                        } else {
                            completedActs.insert(ch.id)
                        }
                    }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isDone ? WFTheme.green : WFTheme.textMuted)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        TagView(ch.isDaily ? "每日行动" : "每周行动", style: ch.isDaily ? .cyan : .gold)
                        
                        Text(actName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDone ? WFTheme.textMuted : WFTheme.textPrimary)
                            .strikethrough(isDone)
                    }
                    
                    Text(ch.Challenge)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                        .lineLimit(1)
                }
                
                Spacer()
                
                CountdownView(targetDate: ch.Expiry?.date, showSeconds: false)
            }
        }
    }
}
