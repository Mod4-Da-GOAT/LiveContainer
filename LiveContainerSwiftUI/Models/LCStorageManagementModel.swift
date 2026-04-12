import Foundation
import Combine

struct LCAppStorageItem: Identifiable {
    let id: String
    let name: String
    let bundlePath: String?
    let bundleSize: Int64?
    let containersSize: Int64
    let tweaksSize: Int64
    let totalSize: Int64
    let version: String
    let bundleIdentifier: String?
    let lastUsedAt: Date?
    let containerDetails: [LCAppStorageContainerItem]
}

struct LCAppStorageContainerItem: Identifiable {
    let id: String
    let name: String
    let size: Int64
}

struct LCStorageBreakdown {
    let totalSize: Int64
    let appBundleSize: Int64
    let containersSize: Int64
    let temporaryFilesSize: Int64
    let appGroupSize: Int64
    let tweaksSize: Int64
    let otherSize: Int64
    let bundleAttributionEnabled: Bool
    let appItems: [LCAppStorageItem]
}

@MainActor
final class LCStorageManagementModel: ObservableObject {
    @Published var breakdown: LCStorageBreakdown?
    @Published var isCalculating = false
    @Published var errorInfo: String?

    func refresh(apps: [LCAppModel], hiddenApps: [LCAppModel]) async {
        guard !isCalculating else {
            return
        }

        isCalculating = true
        defer { isCalculating = false }
        errorInfo = nil
        breakdown = nil

        do {
            breakdown = try await Self.calculateBreakdown(apps: apps, hiddenApps: hiddenApps)
        } catch {
            errorInfo = error.localizedDescription
        }
    }

    private enum StorageCategory {
        case appBundle
        case containers
        case temporaryFiles
        case appGroup
        case tweaks
    }

    private struct ManagedPaths {
        let containerPaths: [URL]
        let tweakPaths: [URL]
        let appInputs: [AppStorageInput]
    }

    private struct AppStorageInput {
        let id: String
        let name: String
        let bundlePath: String?
        let containers: [ContainerStorageInput]
        let tweakPath: URL?
        let version: String
        let bundleIdentifier: String?
        let lastUsedAt: Date?
    }

    private struct ContainerStorageInput {
        let id: String
        let name: String
        let path: URL
    }


    nonisolated private static func calculateBreakdown(apps: [LCAppModel], hiddenApps: [LCAppModel]) async throws -> LCStorageBreakdown {
        let managedPaths = collectManagedPaths(apps: apps, hiddenApps: hiddenApps)
        // Show per-app bundle usage only when every installed app has a reliable bundle path.
        let bundleAttributionEnabled = !managedPaths.appInputs.isEmpty && managedPaths.appInputs.allSatisfy { $0.bundlePath != nil }
        let appItems = try await calculateAppItems(
            from: managedPaths.appInputs,
            bundleAttributionEnabled: bundleAttributionEnabled
        )

        var sizesByCategory: [StorageCategory: Int64] = [:]
        let attributedBundlePaths = bundleAttributionEnabled
            // Keep the page-level app bundle total aligned with the per-app breakdown mode.
            ? managedPaths.appInputs.compactMap { $0.bundlePath.map(URL.init(fileURLWithPath:)) }
            : []
        let knownRoots = uniquePaths([LCPath.docPath, LCPath.lcGroupDocPath])
        let bundleRoots = uniquePaths([LCPath.bundlePath, LCPath.lcGroupBundlePath])
        let containerRoots = uniquePaths([LCPath.dataPath, LCPath.lcGroupDataPath])
        let appGroupRoots = uniquePaths([LCPath.appGroupPath, LCPath.lcGroupAppGroupPath])
        let tweakRoots = uniquePaths([LCPath.tweakPath, LCPath.lcGroupTweakPath])

        try await withThrowingTaskGroup(of: (StorageCategory, Int64).self) { group in
            group.addTask(priority: .utility) {
                (.appBundle, try await calculateCombinedSize(of: attributedBundlePaths))
            }

            group.addTask(priority: .utility) {
                (.containers, try await calculateCombinedSize(of: managedPaths.containerPaths))
            }

            group.addTask(priority: .utility) {
                (.temporaryFiles, try await calculateSize(at: FileManager.default.temporaryDirectory))
            }

            group.addTask(priority: .utility) {
                (.appGroup, try await calculateCombinedSize(of: appGroupRoots))
            }

            group.addTask(priority: .utility) {
                // Surface tweaks as a top-level bucket so managed tweak storage does not disappear into Other.
                (.tweaks, try await calculateCombinedSize(of: managedPaths.tweakPaths))
            }

            for try await (category, size) in group {
                sizesByCategory[category] = size
            }
        }

        let appBundleSize = sizesByCategory[.appBundle] ?? 0
        let containersSize = sizesByCategory[.containers] ?? 0
        let temporaryFilesSize = sizesByCategory[.temporaryFiles] ?? 0
        let appGroupSize = sizesByCategory[.appGroup] ?? 0
        let tweaksSize = sizesByCategory[.tweaks] ?? 0
        let knownRootsSize = try await calculateCombinedSize(of: knownRoots)
        let excludedRoots = bundleRoots + containerRoots + appGroupRoots + tweakRoots
        let looseFilesSize = try await calculateLooseFilesSize(in: knownRoots, excluding: excludedRoots)
        // Other is the residual after explicit categories are removed from the known storage roots, plus loose root-level files.
        let residualOtherSize = max(0, knownRootsSize - appBundleSize - containersSize - appGroupSize - tweaksSize - looseFilesSize)
        let otherSize = residualOtherSize + looseFilesSize

        return LCStorageBreakdown(
            totalSize: appBundleSize + containersSize + temporaryFilesSize + appGroupSize + tweaksSize + otherSize,
            appBundleSize: appBundleSize,
            containersSize: containersSize,
            temporaryFilesSize: temporaryFilesSize,
            appGroupSize: appGroupSize,
            tweaksSize: tweaksSize,
            otherSize: otherSize,
            bundleAttributionEnabled: bundleAttributionEnabled,
            appItems: appItems
        )
    }

    nonisolated private static func collectManagedPaths(apps: [LCAppModel], hiddenApps: [LCAppModel]) -> ManagedPaths {
        let allApps = apps + hiddenApps
        var containerPaths = Set<URL>()
        var tweakPaths = Set<URL>()
        var appInputs: [AppStorageInput] = []

        for app in allApps {
            let containers = app.appInfo.containers.map { container in
                let basePath = container.isShared ? LCPath.lcGroupDataPath : LCPath.dataPath
                let path = basePath.appendingPathComponent(container.folderName)
                let trimmedName = container.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = trimmedName.isEmpty ? container.folderName : trimmedName
                containerPaths.insert(path)
                return ContainerStorageInput(
                    id: container.folderName,
                    name: name,
                    path: path
                )
            }

            let tweak: URL?
            if let tweakFolder = app.appInfo.tweakFolder {
                let basePath = app.appInfo.isShared ? LCPath.lcGroupTweakPath : LCPath.tweakPath
                let path = basePath.appendingPathComponent(tweakFolder)
                tweakPaths.insert(path)
                tweak = path
            } else {
                tweak = nil
            }

            appInputs.append(
                AppStorageInput(
                    id: app.appInfo.bundleIdentifier(),
                    name: app.appInfo.displayName(),
                    bundlePath: app.appInfo.bundlePath(),
                    containers: containers,
                    tweakPath: tweak,
                    version: app.appInfo.version(),
                    bundleIdentifier: app.appInfo.bundleIdentifier(),
                    lastUsedAt: app.appInfo.lastLaunched
                )
            )
        }

        return ManagedPaths(
            containerPaths: Array(containerPaths),
            tweakPaths: Array(tweakPaths),
            appInputs: appInputs
        )
    }

    nonisolated private static func calculateAppItem(
        from input: AppStorageInput,
        bundleAttributionEnabled: Bool
    ) async throws -> LCAppStorageItem {
        var containerDetails: [LCAppStorageContainerItem] = []
        containerDetails.reserveCapacity(input.containers.count)

        var containersSize: Int64 = 0
        for container in input.containers {
            let size = try await calculateSize(at: container.path)
            containersSize += size
            containerDetails.append(
                LCAppStorageContainerItem(
                    id: container.id,
                    name: container.name,
                    size: size
                )
            )
        }

        let tweaksSize: Int64
        if let tweakPath = input.tweakPath {
            tweaksSize = try await calculateSize(at: tweakPath)
        } else {
            tweaksSize = 0
        }

        let bundleSize: Int64?
        if bundleAttributionEnabled, let bundlePath = input.bundlePath {
            bundleSize = try await calculateSize(at: URL(fileURLWithPath: bundlePath))
        } else {
            bundleSize = nil
        }

        return LCAppStorageItem(
            id: input.id,
            name: input.name,
            bundlePath: input.bundlePath,
            bundleSize: bundleSize,
            containersSize: containersSize,
            tweaksSize: tweaksSize,
            totalSize: (bundleSize ?? 0) + containersSize + tweaksSize,
            version: input.version,
            bundleIdentifier: input.bundleIdentifier,
            lastUsedAt: input.lastUsedAt,
            containerDetails: containerDetails
        )
    }

    nonisolated private static func calculateAppItems(
        from inputs: [AppStorageInput],
        bundleAttributionEnabled: Bool
    ) async throws -> [LCAppStorageItem] {
        var appItems: [LCAppStorageItem] = []
        appItems.reserveCapacity(inputs.count)

        try await withThrowingTaskGroup(of: LCAppStorageItem.self) { group in
            for input in inputs {
                group.addTask(priority: .utility) {
                    try await calculateAppItem(
                        from: input,
                        bundleAttributionEnabled: bundleAttributionEnabled
                    )
                }
            }

            for try await item in group {
                appItems.append(item)
            }
        }

        return appItems.sorted {
            if $0.totalSize == $1.totalSize {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.totalSize > $1.totalSize
        }
    }

    nonisolated private static func calculateCombinedSize(of urls: [URL]) async throws -> Int64 {
        try await withThrowingTaskGroup(of: Int64.self) { group in
            for url in uniquePaths(urls) {
                group.addTask(priority: .utility) {
                    try await calculateSize(at: url)
                }
            }

            var totalSize: Int64 = 0
            for try await size in group {
                totalSize += size
            }
            return totalSize
        }
    }

    nonisolated private static func uniquePaths(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let standardizedPath = url.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    nonisolated private static func calculateLooseFilesSize(in roots: [URL], excluding excludedRoots: [URL]) async throws -> Int64 {
        let fileManager = FileManager.default
        let excludedPaths = Set(excludedRoots.map { $0.standardizedFileURL.path })
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]

        var totalSize: Int64 = 0

        for root in roots {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            )

            for child in children {
                try Task.checkCancellation()

                let standardizedChildPath = child.standardizedFileURL.path
                guard !excludedPaths.contains(standardizedChildPath) else {
                    continue
                }

                let resourceValues = try child.resourceValues(forKeys: resourceKeys)
                guard resourceValues.isRegularFile == true else {
                    continue
                }

                let fileSize = resourceValues.totalFileAllocatedSize
                    ?? resourceValues.fileAllocatedSize
                    ?? resourceValues.fileSize
                    ?? 0
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    nonisolated private static func calculateSize(at url: URL) async throws -> Int64 {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues.isRegularFile == true else {
                continue
            }

            let fileSize = resourceValues.totalFileAllocatedSize
                ?? resourceValues.fileAllocatedSize
                ?? resourceValues.fileSize
                ?? 0
            totalSize += Int64(fileSize)
        }

        return totalSize
    }
}

