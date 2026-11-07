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
        let info = dict.challengeInfo(ch.Challenge)
        let isHard = ch.Challenge.contains("/WeeklyHard/")
        let badgeStyle: TagStyle = ch.isDaily ? .cyan : (isHard ? .red : .gold)
        let badgeText = ch.isDaily ? "每日 +\(info.points)" : (isHard ? "精英周常 +\(info.points)" : "每周 +\(info.points)")
        
        WFCard {
            HStack(alignment: .top, spacing: 10) {
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
                        .font(.system(size: 20))
                        .foregroundColor(isDone ? WFTheme.green : WFTheme.textMuted)
                        .padding(.top, 2)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TagView(badgeText, style: badgeStyle)
                        
                        Spacer()
                        
                        CountdownView(targetDate: ch.Expiry?.date, showSeconds: false)
                    }
                    
                    Text(info.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isDone ? WFTheme.textMuted : WFTheme.textPrimary)
                        .strikethrough(isDone)
                    
                    Text(info.desc)
                        .font(.system(size: 12))
                        .foregroundColor(isDone ? WFTheme.textMuted : WFTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
