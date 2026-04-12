import SwiftUI

private struct LCInstalledAppIconView: View {
    // Cache icon results per bundle path so the settings list does not redo icon work on every row update.
    @MainActor private static var iconCache: [String: UIImage?] = [:]

    let bundlePath: String?
    let iconSize: CGFloat
    let cornerRadius: CGFloat

    @State private var icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.tertiary.opacity(0.18))
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
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

    var body: some View {
        Section("lc.storage.installedApps".loc) {
            content
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

    private func appRow(_ appItem: LCAppStorageItem) -> some View {
        NavigationLink {
            LCAppStorageDetailView(appItem: appItem)
        } label: {
            HStack(spacing: 12) {
                LCInstalledAppIconView(
                    bundlePath: appItem.bundlePath,
                    iconSize: 28,
                    cornerRadius: 7
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(appItem.name)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let lastUsedAt = appItem.lastUsedAt {
                        Text(formatStorageDate(lastUsedAt))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                Text(formatStorageSize(appItem.totalSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LCAppStorageSummaryHeaderView: View {
    let appItem: LCAppStorageItem

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LCInstalledAppIconView(
                bundlePath: appItem.bundlePath,
                iconSize: iconSize,
                cornerRadius: iconSize * 0.22
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(appItem.name)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(appItem.version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let bundleIdentifier = appItem.bundleIdentifier {
                    Text(bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct LCAppStorageDetailView: View {
    let appItem: LCAppStorageItem

    var body: some View {
        Form {
            Section {
                LCAppStorageSummaryHeaderView(appItem: appItem)
                    .listRowInsets(
                        EdgeInsets(
                            top: 10,
                            leading: 16,
                            bottom: 10,
                            trailing: 16
                        )
                    )

                if let bundleSize = appItem.bundleSize {
                    appSummaryRow(title: "lc.storage.appBundle".loc, size: bundleSize)
                }

                appSummaryRow(title: "lc.storage.containers".loc, size: appItem.containersSize)

                if appItem.tweaksSize > 0 {
                    appSummaryRow(title: "lc.storage.tweaks".loc, size: appItem.tweaksSize)
                }
            }

            if !appItem.containerDetails.isEmpty {
                Section("lc.storage.containers".loc) {
                    ForEach(appItem.containerDetails, id: \.id) { container in
                        appContainerRow(container)
                    }
                }
            }
        }
        .navigationTitle(appItem.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func appSummaryRow(title: String, size: Int64) -> some View {
    HStack(spacing: 12) {
        Text(title)
            .lineLimit(1)
            .truncationMode(.tail)

        Spacer(minLength: 12)

        Text(formatStorageSize(size))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private func appContainerRow(_ container: LCAppStorageContainerItem) -> some View {
    HStack(spacing: 12) {
        Text(container.name)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)

        Spacer(minLength: 12)

        Text(formatStorageSize(container.size))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .padding(.vertical, 2)
}

private func formatStorageDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

private func formatStorageSize(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}