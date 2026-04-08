import SwiftUI

private struct LCInstalledAppIconView: View {
    // Cache icon results per bundle path so the settings list does not redo icon work on every row update.
    @MainActor private static var iconCache: [String: UIImage?] = [:]

    let bundlePath: String?

    @State private var icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.tertiary.opacity(0.18))
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        // Keep the icon compact so the row still reads like Settings, not an app launcher.
        .frame(width: 28, height: 28)
        // Match the small rounded-rectangle feel of iOS settings-style app icons at this size.
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            icon = nil
        }
        // Clear the visible icon as soon as the row is reused for a different app.
        .onChange(of: bundlePath) { _ in
            icon = nil
        }
        .task(id: bundlePath) {
            await loadIconIfNeeded(for: bundlePath)
        }
    }

    @MainActor
    private func loadIconIfNeeded(for bundlePath: String?) async {
        icon = nil

        guard let bundlePath else {
            return
        }

        if Self.iconCache.keys.contains(bundlePath) {
            icon = Self.iconCache[bundlePath] ?? nil
            return
        }

        let loadedIcon = await loadIcon(for: bundlePath)

        // Ignore results from an outdated task if the row has already been rebound to another app.
        guard !Task.isCancelled, self.bundlePath == bundlePath else {
            return
        }

        Self.iconCache[bundlePath] = loadedIcon
        icon = loadedIcon
    }

    private func loadIcon(for bundlePath: String) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask(priority: .utility) {
                guard let appInfo = LCAppInfo(bundlePath: bundlePath) else {
                    return nil
                }

                return appInfo.iconIsDarkIcon(false)
            }

            return await group.next() ?? nil
        }
    }
}

private enum LCStorageSummaryCategory {
    case appBundle
    case containers
    case appGroup
    case tweaks
    case temporaryFiles
    case looseFiles
    case other
}

private struct LCStorageSummaryDisplayItem: Identifiable {
    let category: LCStorageSummaryCategory
    let size: Int64

    var id: LCStorageSummaryCategory { category }

    var title: String {
        switch category {
        case .appBundle:
            return "lc.storage.appBundle".loc
        case .containers:
            return "lc.storage.containers".loc
        case .appGroup:
            return "lc.storage.appGroupData".loc
        case .tweaks:
            return "lc.storage.tweaks".loc
        case .temporaryFiles:
            return "lc.storage.temporaryFiles".loc
        case .looseFiles:
            return "lc.storage.looseFiles".loc
        case .other:
            return "lc.storage.other".loc
        }
    }

    var color: Color {
        switch category {
        case .appBundle:
            return .blue
        case .containers:
            return .green
        case .appGroup:
            return .purple
        case .tweaks:
            return .pink
        case .temporaryFiles:
            return .orange
        case .looseFiles:
            return .teal
        case .other:
            return .gray
        }
    }
}

private struct LCStorageSummaryBarView: View {
    let items: [LCStorageSummaryDisplayItem]

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        if totalSize > 0 {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        Rectangle()
                            .fill(item.color)
                            .frame(width: segmentWidth(for: item, totalWidth: geometry.size.width))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
    }

    private func segmentWidth(for item: LCStorageSummaryDisplayItem, totalWidth: CGFloat) -> CGFloat {
        guard totalSize > 0 else { return 0 }

        let spacing: CGFloat = 2
        let totalSpacing = max(0, CGFloat(items.count - 1) * spacing)
        let availableWidth = max(0, totalWidth - totalSpacing)

        return max(0, availableWidth * CGFloat(item.size) / CGFloat(totalSize))
    }
}

struct LCStorageSummarySection: View {
    let breakdown: LCStorageBreakdown?
    let isCalculating: Bool
    let errorInfo: String?

    var body: some View {
        Section("lc.storage.totalStorage".loc) {
            VStack(alignment: .leading, spacing: 12) {
                if isCalculating {
                    ProgressView("lc.storage.calculating".loc)
                        .controlSize(.regular)
                }

                if let breakdown {
                    Text(formatStorageSize(breakdown.totalSize))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                if let errorInfo {
                    Text(errorInfo)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let breakdown {
                    let displayItems = self.displayItems

                    if !displayItems.isEmpty {
                        LCStorageSummaryBarView(items: displayItems)
                            .padding(.top, 2)
                    }

                    // Keep the larger category set flattened into one settings-style summary so total-first scanning still works.
                    VStack(spacing: 0) {
                        // Hide zero-sized categories to keep the expanded summary readable even with the larger category set.
                        ForEach(displayItems) { item in
                            storageRow(title: item.title, size: item.size, color: item.color)
                        }
                    }
                    .padding(.top, 4)
                }

            }
            .padding(.vertical, 2)
        }
    }

    private var displayItems: [LCStorageSummaryDisplayItem] {
        guard let breakdown else {
            return []
        }

        var items: [LCStorageSummaryDisplayItem] = []

        if breakdown.bundleAttributionEnabled, breakdown.appBundleSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .appBundle,
                    size: breakdown.appBundleSize
                )
            )
        }

        if breakdown.containersSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .containers,
                    size: breakdown.containersSize
                )
            )
        }

        if breakdown.temporaryFilesSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .temporaryFiles,
                    size: breakdown.temporaryFilesSize
                )
            )
        }

        if breakdown.appGroupSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .appGroup,
                    size: breakdown.appGroupSize
                )
            )
        }

        if breakdown.tweaksSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .tweaks,
                    size: breakdown.tweaksSize
                )
            )
        }

        if breakdown.looseFilesSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .looseFiles,
                    size: breakdown.looseFilesSize
                )
            )
        }

        // Treat Other as the residual bucket now that more explicit categories are broken out above.
        if breakdown.otherSize > 0 {
            items.append(
                LCStorageSummaryDisplayItem(
                    category: .other,
                    size: breakdown.otherSize
                )
            )
        }

        return items
    }

    @ViewBuilder
    private func storageRow(title: String, size: Int64, color: Color?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color ?? .clear)
                    .frame(width: 8, height: 8)
                    .opacity(color == nil ? 0 : 1)
                    .accessibilityHidden(true)
                Text(title)
            }
            Spacer(minLength: 12)
            Text(formatStorageSize(size))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

struct LCInstalledAppsSection: View {
    let breakdown: LCStorageBreakdown?

    @State private var expandedAppIDs: Set<String> = []

    var body: some View {
        Section("lc.storage.installedApps".loc) {
            content
        }
        .onChange(of: breakdown?.appItems.map(\.id) ?? []) { appIDs in
            expandedAppIDs.formIntersection(appIDs)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let breakdown {
            if breakdown.appItems.isEmpty {
                Text("lc.storage.noAppStorageData".loc)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(breakdown.appItems, id: \.id) { appItem in
                    appRow(appItem)
                }
            }
        }
    }

    @ViewBuilder
    private func appRow(_ appItem: LCAppStorageItem) -> some View {
        let isExpanded = expandedAppIDs.contains(appItem.id)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                toggleExpanded(appID: appItem.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Keep the icon in the top-level row only so expanded storage details stay text-first.
                LCInstalledAppIconView(bundlePath: appItem.bundlePath)

                Text(appItem.name)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(formatStorageSize(appItem.totalSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Expose the expanded state on the row because the chevron is decorative only.
        .accessibilityValue(isExpanded ? Text("lc.common.expanded".loc) : Text("lc.common.collapsed".loc))
        .accessibilityHint(Text("lc.storage.installedAppsToggleHint".loc))

        if isExpanded {
            if let bundleSize = appItem.bundleSize {
                appSummaryRow(
                    title: "lc.storage.appBundle".loc,
                    size: bundleSize
                )
            }

            appSummaryRow(
                title: "lc.storage.containers".loc,
                size: appItem.containersSize
            )

            ForEach(appItem.containerDetails, id: \.id) { container in
                appContainerRow(container)
            }

            if appItem.tweaksSize > 0 {
                appSummaryRow(
                    title: "lc.storage.tweaks".loc,
                    size: appItem.tweaksSize
                )
            }
        }
    }

    private func appSummaryRow(title: String, size: Int64) -> some View {
        HStack {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 20)

            Spacer()

            Text(formatStorageSize(size))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func appContainerRow(_ container: LCAppStorageContainerItem) -> some View {
        HStack {
            Text(container.name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 36)

            Spacer()

            Text(formatStorageSize(container.size))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func toggleExpanded(appID: String) {
        if expandedAppIDs.contains(appID) {
            expandedAppIDs.remove(appID)
        } else {
            expandedAppIDs.insert(appID)
        }
    }
}

private func formatStorageSize(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}
