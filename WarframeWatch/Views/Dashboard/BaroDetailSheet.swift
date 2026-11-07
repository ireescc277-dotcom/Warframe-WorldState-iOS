import SwiftUI

public struct BaroDetailSheet: View {
    public let trader: VoidTrader
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .ducatsDesc
    
    private let dict = DictionaryService.shared
    
    public enum SortOption: String, CaseIterable, Identifiable {
        case ducatsDesc = "杜卡德 (高→低)"
        case ducatsAsc = "杜卡德 (低→高)"
        case creditsDesc = "现金 (高→低)"
        public var id: String { rawValue }
    }
    
    public init(trader: VoidTrader) {
        self.trader = trader
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Header info
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("虚空商人 · \(trader.Character)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(WFTheme.purple)
                            
                            Text("停留地点: \(dict.nodeName(trader.Node))")
                                .font(.system(size: 12))
                                .foregroundColor(WFTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        CountdownView(targetDate: trader.Expiry?.date, prefix: "离开还有")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Search bar & sort
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(WFTheme.textMuted)
                            TextField("搜索商品名称...", text: $searchText)
                                .foregroundColor(WFTheme.textPrimary)
                        }
                        .padding(8)
                        .background(WFTheme.panelElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Picker("排序", selection: $sortOption) {
                            ForEach(SortOption.allCases) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(WFTheme.gold)
                    }
                    .padding(.horizontal)
                    
                    // Manifest List
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredManifest) { item in
                                itemRow(item: item)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("商品清单 (\(trader.Manifest?.count ?? 0)件)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(WFTheme.cyan)
                }
            }
        }
    }
    
    private var filteredManifest: [VoidTraderItem] {
        guard let list = trader.Manifest else { return [] }
        let filtered = list.filter { item in
            if searchText.isEmpty { return true }
            let name = dict.itemName(item.ItemType)
            return name.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortOption {
        case .ducatsDesc:
            return filtered.sorted { ($0.PrimePrice ?? 0) > ($1.PrimePrice ?? 0) }
        case .ducatsAsc:
            return filtered.sorted { ($0.PrimePrice ?? 0) < ($1.PrimePrice ?? 0) }
        case .creditsDesc:
            return filtered.sorted { ($0.RegularPrice ?? 0) > ($1.RegularPrice ?? 0) }
        }
    }
    
    @ViewBuilder
    private func itemRow(item: VoidTraderItem) -> some View {
        let name = dict.itemName(item.ItemType)
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(item.ItemType.split(separator: "/").last.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(WFTheme.textMuted)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let ducats = item.PrimePrice {
                    HStack(spacing: 3) {
                        Text("\(ducats)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(WFTheme.gold)
                        Text("杜卡德")
                            .font(.system(size: 10))
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
                
                if let credits = item.RegularPrice {
                    HStack(spacing: 3) {
                        Text("\(credits.formatted())")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(WFTheme.cyan)
                        Text("现金")
                            .font(.system(size: 10))
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
            }
        }
        .padding(10)
        .background(WFTheme.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(WFTheme.border, lineWidth: 1)
        )
    }
}
