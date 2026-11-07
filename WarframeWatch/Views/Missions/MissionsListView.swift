import SwiftUI

public struct MissionsListView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    private let dict = DictionaryService.shared
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Category Picker Bar
                    categoryPicker
                    
                    // Extra Filters for Fissures
                    if vm.selectedMissionCategory == .fissures {
                        fissureFiltersBar
                    }
                    
                    // Missions List Feed
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            switch vm.selectedMissionCategory {
                            case .fissures:
                                fissuresList
                            case .alerts:
                                alertsList
                            case .invasions:
                                invasionsList
                            case .storms:
                                stormsList
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 90)
                    }
                    .refreshable {
                        await vm.refreshData()
                    }
                }
            }
            .navigationTitle("任务与活动")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Category Picker
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorldStateViewModel.MissionCategory.allCases) { cat in
                    let isSelected = vm.selectedMissionCategory == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.selectedMissionCategory = cat
                        }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? WFTheme.gold : WFTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? WFTheme.gold.opacity(0.15) : WFTheme.panelElevated)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? WFTheme.gold.opacity(0.4) : WFTheme.border, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
    
    // MARK: - Fissures Extra Filter Bar
    private var fissureFiltersBar: some View {
        HStack {
            // Era Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    eraPill(title: "全部纪元", value: nil)
                    eraPill(title: "古纪 T1", value: "VoidT1")
                    eraPill(title: "前纪 T2", value: "VoidT2")
                    eraPill(title: "中纪 T3", value: "VoidT3")
                    eraPill(title: "后纪 T4", value: "VoidT4")
                    eraPill(title: "安魂 T5", value: "VoidT5")
                    eraPill(title: "全能 T6", value: "VoidT6")
                }
                .padding(.horizontal)
            }
            
            // Steel Path Toggle Button
            Button {
                withAnimation {
                    vm.isSteelPathOnly.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 10))
                    Text("钢韧")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(vm.isSteelPathOnly ? WFTheme.red : WFTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(vm.isSteelPathOnly ? WFTheme.red.opacity(0.18) : WFTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(vm.isSteelPathOnly ? WFTheme.red.opacity(0.5) : WFTheme.border, lineWidth: 1)
                )
            }
            .padding(.trailing)
        }
    }
    
    @ViewBuilder
    private func eraPill(title: String, value: String?) -> some View {
        let isSelected = vm.selectedEra == value
        Button {
            withAnimation {
                vm.selectedEra = value
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(isSelected ? WFTheme.cyan : WFTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isSelected ? WFTheme.cyan.opacity(0.15) : WFTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? WFTheme.cyan.opacity(0.5) : WFTheme.border, lineWidth: 1)
                )
        }
    }
    
    // MARK: - Sub-Lists
    @ViewBuilder
    private var fissuresList: some View {
        let items = vm.filteredFissures
        if items.isEmpty {
            emptyStateView(text: "暂无符合筛选的虚空裂隙")
        } else {
            ForEach(items) { fissure in
                FissureRowView(fissure: fissure)
            }
        }
    }
    
    @ViewBuilder
    private var alertsList: some View {
        let items = vm.filteredAlerts
        if items.isEmpty {
            emptyStateView(text: "暂无活跃的限时警报任务")
        } else {
            ForEach(items) { alert in
                AlertRowView(alert: alert)
            }
        }
    }
    
    @ViewBuilder
    private var invasionsList: some View {
        let items = vm.filteredInvasions
        if items.isEmpty {
            emptyStateView(text: "暂无进行中的入侵事件")
        } else {
            ForEach(items) { invasion in
                InvasionRowView(invasion: invasion)
            }
        }
    }
    
    @ViewBuilder
    private var stormsList: some View {
        let items = vm.filteredVoidStorms
        if items.isEmpty {
            emptyStateView(text: "暂无活跃的虚空风暴")
        } else {
            ForEach(items) { storm in
                WFCard {
                    HStack {
                        TagView(dict.tierName(storm.ActiveMissionTier), style: .purple, icon: "wind")
                        Text(dict.nodeName(storm.Node))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(WFTheme.textPrimary)
                        
                        Spacer()
                        
                        CountdownView(targetDate: storm.Expiry?.date)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyStateView(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 32))
                .foregroundColor(WFTheme.textMuted)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(WFTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
