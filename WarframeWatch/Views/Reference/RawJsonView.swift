import SwiftUI

public struct RawJsonView: View {
    public let worldState: WorldState?
    @Environment(\.dismiss) private var dismiss
    
    @State private var jsonString: String = ""
    @State private var copied: Bool = false
    @State private var filterQuery: String = ""
    
    public init(worldState: WorldState?) {
        self.worldState = worldState
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080C11").ignoresSafeArea()
                
                VStack(spacing: 8) {
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(WFTheme.textMuted)
                            TextField("筛选 JSON 字段...", text: $filterQuery)
                                .foregroundColor(WFTheme.textPrimary)
                        }
                        .padding(8)
                        .background(WFTheme.panelElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = jsonString
                            #elseif os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(jsonString, forType: .string)
                            #endif
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "已复制" : "复制全部")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(WFTheme.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(WFTheme.cyan.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    ScrollView([.horizontal, .vertical]) {
                        Text(displayString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "A9C4D4"))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle("原始 JSON 数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundColor(WFTheme.cyan)
                }
            }
            .task {
                generateJson()
            }
        }
    }
    
    private var displayString: String {
        if filterQuery.isEmpty {
            return jsonString
        }
        let lines = jsonString.components(separatedBy: .newlines)
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterQuery) }
        return filtered.joined(separator: "\n")
    }
    
    private func generateJson() {
        guard let state = worldState else {
            jsonString = "{}"
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state), let str = String(data: data, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "无法格式化数据"
        }
    }
}
