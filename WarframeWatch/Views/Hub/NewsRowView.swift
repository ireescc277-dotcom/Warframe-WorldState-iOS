import SwiftUI

public struct NewsRowView: View {
    public let news: EventNews
    
    private let dict = DictionaryService.shared
    
    public init(news: EventNews) {
        self.news = news
    }
    
    public var body: some View {
        WFCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dict.localizedDesc(news.preferredTitle))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(WFTheme.textPrimary)
                            .lineLimit(2)
                        
                        if let date = news.Date?.date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                    
                    Spacer()
                    
                    if let prop = news.Prop, let url = URL(string: prop) {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Text("详情")
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(WFTheme.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(WFTheme.cyan.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}
