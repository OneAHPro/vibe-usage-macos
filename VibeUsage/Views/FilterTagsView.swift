import SwiftUI

enum FilterDimension: CaseIterable, Hashable {
    case hostname
    case source
    case model
    case project

    var icon: String {
        switch self {
        case .hostname: "desktopcomputer"
        case .source: "terminal"
        case .model: "cpu"
        case .project: "folder"
        }
    }

    var label: String {
        switch self {
        case .hostname: "终端"
        case .source: "工具"
        case .model: "模型"
        case .project: "项目"
        }
    }
}

struct FilterButtonAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [FilterDimension: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [FilterDimension: Anchor<CGRect>],
        nextValue: () -> [FilterDimension: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

enum FilterPanelLayout {
    static let preferredWidth: CGFloat = 240
    static let maxHeight: CGFloat = 260
    static let rowHeight: CGFloat = 28
    static let verticalPadding: CGFloat = 8

    static func panelHeight(
        for dimension: FilterDimension,
        buckets: [UsageBucket],
        expandedModelFamilies: Set<String>
    ) -> CGFloat {
        let rowCount: Int
        switch dimension {
        case .hostname:
            rowCount = Set(buckets.map(\.hostname)).count
        case .source:
            rowCount = Set(buckets.map(\.source)).count
        case .project:
            rowCount = Set(buckets.map(\.project)).count
        case .model:
            let models = Array(Set(buckets.map(\.model))).sorted()
            rowCount = groupModelsByFamily(models).reduce(into: 0) { count, group in
                let familyKey = group.family?.key ?? "other"
                count += 1
                if expandedModelFamilies.contains(familyKey) {
                    count += group.models.count
                }
            }
        }

        let contentHeight = CGFloat(max(rowCount, 1)) * rowHeight
        return min(max(contentHeight, rowHeight), maxHeight - verticalPadding) + verticalPadding
    }
}

struct FilterTagsView: View {
    @Environment(AppState.self) private var appState
    @Binding private var openFilter: FilterDimension?
    private let filterGap: CGFloat = 8
    private let filterRowHeight: CGFloat = 28

    init(openFilter: Binding<FilterDimension?>) {
        _openFilter = openFilter
    }

    private var uniqueSources: [String] {
        Array(Set(appState.buckets.map(\.source))).sorted()
    }

    private var uniqueModels: [String] {
        Array(Set(appState.buckets.map(\.model))).sorted()
    }

    private var uniqueProjects: [String] {
        Array(Set(appState.buckets.map(\.project))).sorted()
    }

    private var uniqueHostnames: [String] {
        Array(Set(appState.buckets.map(\.hostname))).sorted()
    }

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                timeRangeSelector

                Spacer(minLength: 0)

                if !appState.filters.isEmpty {
                    Button {
                        state.filters.clear()
                    } label: {
                        Text("清除")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("清除筛选")
                }
            }

            filterGrid
                .zIndex(20)
        }
    }

    private var filterGrid: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let count = CGFloat(FilterDimension.allCases.count)
            let buttonWidth = max((availableWidth - filterGap * (count - 1)) / count, 0)

            HStack(spacing: filterGap) {
                ForEach(FilterDimension.allCases, id: \.self) { dimension in
                    filterButton(for: dimension)
                        .frame(width: buttonWidth)
                        .anchorPreference(
                            key: FilterButtonAnchorPreferenceKey.self,
                            value: .bounds,
                            transform: { [dimension: $0] }
                        )
                }
            }
            .frame(width: availableWidth, height: filterRowHeight, alignment: .leading)
        }
        .frame(height: filterRowHeight)
    }

    private var timeRangeSelector: some View {
        HStack(spacing: 1) {
            ForEach(TimeRange.allCases, id: \.rawValue) { range in
                let isActive = appState.timeRange == range
                Button {
                    guard !appState.isLoadingData, appState.timeRange != range else { return }
                    Task { await appState.selectTimeRange(range) }
                } label: {
                    Text(range.displayLabel)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? AppTheme.primaryText : AppTheme.secondaryText)
                        .frame(height: 24)
                        .padding(.horizontal, 9)
                        .background(isActive ? AppTheme.selectionBackground : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoadingData)
            }
        }
        .padding(2)
        .background(AppTheme.subtleSurface)
        .clipShape(Capsule())
    }

    private func filterButton(for dimension: FilterDimension) -> some View {
        let enabled = hasValues(for: dimension)
        let selectedCount = selectedValues(for: dimension).count
        let isOpen = openFilter == dimension
        let isActive = selectedCount > 0
        let summary = summaryText(for: dimension)

        return Button {
            guard enabled else { return }
            openFilter = isOpen ? nil : dimension
        } label: {
            HStack(spacing: 6) {
                Image(systemName: dimension.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive || isOpen ? AppTheme.primaryText : AppTheme.secondaryText)
                    .frame(width: 13)
                    .layoutPriority(1)

                Text(dimension.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive || isOpen ? AppTheme.primaryText : AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(2)

                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? AppTheme.primaryText : AppTheme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .frame(width: 10)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: filterRowHeight)
            .background(isActive || isOpen ? AppTheme.selectionBackground : AppTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.separator, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func hasValues(for dimension: FilterDimension) -> Bool {
        switch dimension {
        case .hostname: !uniqueHostnames.isEmpty
        case .source: !uniqueSources.isEmpty
        case .model: !uniqueModels.isEmpty
        case .project: !uniqueProjects.isEmpty
        }
    }

    private func selectedValues(for dimension: FilterDimension) -> Set<String> {
        switch dimension {
        case .hostname: appState.filters.hostnames
        case .source: appState.filters.sources
        case .model: appState.filters.models
        case .project: appState.filters.projects
        }
    }

    private func summaryText(for dimension: FilterDimension) -> String {
        let selectedCount = selectedValues(for: dimension).count
        return selectedCount == 0 ? "全部" : "\(selectedCount) 项"
    }

}

struct FilterPanelView: View {
    @Environment(AppState.self) private var appState
    let dimension: FilterDimension
    @Binding var expandedModelFamilies: Set<String>
    let height: CGFloat

    private var uniqueSources: [String] {
        Array(Set(appState.buckets.map(\.source))).sorted()
    }

    private var uniqueModels: [String] {
        Array(Set(appState.buckets.map(\.model))).sorted()
    }

    private var uniqueProjects: [String] {
        Array(Set(appState.buckets.map(\.project))).sorted()
    }

    private var uniqueHostnames: [String] {
        Array(Set(appState.buckets.map(\.hostname))).sorted()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            panelContent
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: max(height - FilterPanelLayout.verticalPadding, 0))
        .padding(.vertical, FilterPanelLayout.verticalPadding / 2)
        .background(AppTheme.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.separator, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 8)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch dimension {
        case .hostname:
            optionList(values: uniqueHostnames, selected: appState.filters.hostnames) { value in
                toggle(value, in: &appState.filters.hostnames)
            }
        case .source:
            optionList(values: uniqueSources, selected: appState.filters.sources) { value in
                toggle(value, in: &appState.filters.sources)
            }
        case .model:
            modelOptions
        case .project:
            optionList(values: uniqueProjects, selected: appState.filters.projects) { value in
                toggle(value, in: &appState.filters.projects)
            }
        }
    }

    private func optionList(
        values: [String],
        selected: Set<String>,
        toggle: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(values, id: \.self) { value in
                optionRow(title: value.isEmpty ? "未知" : value, isSelected: selected.contains(value)) {
                    toggle(value)
                }
            }
        }
    }

    private var modelOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groupModelsByFamily(uniqueModels).enumerated()), id: \.offset) { _, group in
                let familyKey = group.family?.key ?? "other"
                let familyLabel = group.family?.label ?? "其他"
                let familyModels = Set(group.models)
                let selectedInFamily = familyModels.intersection(appState.filters.models)
                let allSelected = selectedInFamily.count == familyModels.count && !familyModels.isEmpty
                let someSelected = !selectedInFamily.isEmpty && !allSelected
                let isExpanded = expandedModelFamilies.contains(familyKey)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Button {
                            if allSelected {
                                appState.filters.models.subtract(familyModels)
                            } else {
                                appState.filters.models.formUnion(familyModels)
                            }
                        } label: {
                            checkRowContent(
                                title: familyLabel,
                                isSelected: allSelected,
                                isMixed: someSelected
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if isExpanded {
                                expandedModelFamilies.remove(familyKey)
                            } else {
                                expandedModelFamilies.insert(familyKey)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }

                    if isExpanded {
                        ForEach(group.models, id: \.self) { value in
                            optionRow(
                                title: value.isEmpty ? "未知" : value,
                                isSelected: appState.filters.models.contains(value),
                                indent: 19
                            ) {
                                toggle(value, in: &appState.filters.models)
                            }
                        }
                    }
                }
            }
        }
    }

    private func optionRow(
        title: String,
        isSelected: Bool,
        indent: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            checkRowContent(title: title, isSelected: isSelected, indent: indent)
        }
        .buttonStyle(.plain)
    }

    private func checkRowContent(
        title: String,
        isSelected: Bool,
        isMixed: Bool = false,
        indent: CGFloat = 0
    ) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                checkbox(isSelected: isSelected, isMixed: isMixed)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected || isMixed ? AppTheme.primaryText : AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, indent)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: FilterPanelLayout.rowHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func checkbox(isSelected: Bool, isMixed: Bool = false) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected || isMixed ? AppTheme.primaryText : Color.clear)
                .frame(width: 13, height: 13)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(AppTheme.tertiaryText, lineWidth: isSelected || isMixed ? 0 : 1)
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.windowBackground)
            } else if isMixed {
                Rectangle()
                    .fill(AppTheme.windowBackground)
                    .frame(width: 7, height: 1.5)
            }
        }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}

/// Simple flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
