//
//  LCUpdatesView.swift
//  LiveContainerSwiftUI
//

import SwiftUI

struct LCUpdatesView: View {
    @EnvironmentObject private var sharedModel: SharedModel

    /// Each entry: the installed app model + the best available update version
    private struct UpdateEntry: Identifiable {
        let id: ObjectIdentifier
        let app: LCAppModel
        let newVersion: AltStoreSourceAppVersion

        init(app: LCAppModel, newVersion: AltStoreSourceAppVersion) {
            self.id = ObjectIdentifier(app)
            self.app = app
            self.newVersion = newVersion
        }
    }

    @State private var isRefreshing = false
    @State private var isUpdatingAll = false
    @State private var updatingBundleIds: Set<String> = []

    private var allApps: [LCAppModel] {
        sharedModel.apps + sharedModel.hiddenApps
    }

    private var updateEntries: [UpdateEntry] {
        let sources = sharedModel.sourcesViewModel.sources
        return allApps.compactMap { app in
            guard let bundleId = app.appInfo.bundleIdentifier(),
                  let installedVersion = app.appInfo.version(),
                  let best = LCAppListView.bestUpdateVersion(
                    for: bundleId,
                    installedVersion: installedVersion,
                    sources: sources
                  ) else { return nil }
            return UpdateEntry(app: app, newVersion: best)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if sharedModel.sourcesViewModel.isRefreshingAll && updateEntries.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Checking for updates…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if updateEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        Text("All apps are up to date")
                            .font(.title2.bold())
                        Text("Pull down to check again")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(updateEntries) { entry in
                        UpdateRowView(
                            entry_app: entry.app,
                            entry_newVersion: entry.newVersion,
                            isUpdating: updatingBundleIds.contains(entry.app.appInfo.bundleIdentifier() ?? "")
                        ) {
                            triggerInstall(downloadURL: entry.newVersion.downloadURL,
                                           bundleId: entry.app.appInfo.bundleIdentifier() ?? "")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Updates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if sharedModel.sourcesViewModel.isRefreshingAll {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Button {
                            Task { await refreshSources() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !updateEntries.isEmpty {
                        Button {
                            Task { await updateAll() }
                        } label: {
                            if isUpdatingAll {
                                ProgressView().progressViewStyle(.circular)
                            } else {
                                Text("Update All").bold()
                            }
                        }
                        .disabled(isUpdatingAll)
                    }
                }
            }
            .refreshable {
                await refreshSources()
            }
        }
    }

    private func refreshSources() async {
        isRefreshing = true
        await sharedModel.sourcesViewModel.refreshAllSources()
        isRefreshing = false
    }

    private func triggerInstall(downloadURL: URL, bundleId: String) {
        updatingBundleIds.insert(bundleId)
        withAnimation { DataManager.shared.model.selectedTab = .apps }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.InstallAppNotification,
                object: ["url": downloadURL]
            )
            // Clear after a short delay — the install dialog will have appeared
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                updatingBundleIds.remove(bundleId)
            }
        }
    }

    private func updateAll() async {
        isUpdatingAll = true
        let entries = updateEntries
        // Queue them sequentially with a small delay between each so the
        // install notification handler can process them one at a time.
        for entry in entries {
            guard let bundleId = entry.app.appInfo.bundleIdentifier() else { continue }
            updatingBundleIds.insert(bundleId)
            NotificationCenter.default.post(
                name: NSNotification.InstallAppNotification,
                object: ["url": entry.newVersion.downloadURL]
            )
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s between installs
            updatingBundleIds.remove(bundleId)
        }
        isUpdatingAll = false
        // Switch to apps tab so the user can see progress
        withAnimation { DataManager.shared.model.selectedTab = .apps }
    }
}

// MARK: - Row

private struct UpdateRowView: View {
    let entry_app: LCAppModel
    let entry_newVersion: AltStoreSourceAppVersion
    let isUpdating: Bool
    let onUpdate: () -> Void

    @State private var icon: UIImage

    init(entry_app: LCAppModel, entry_newVersion: AltStoreSourceAppVersion, isUpdating: Bool, onUpdate: @escaping () -> Void) {
        self.entry_app = entry_app
        self.entry_newVersion = entry_newVersion
        self.isUpdating = isUpdating
        self.onUpdate = onUpdate
        _icon = State(initialValue: entry_app.appInfo.iconIsDarkIcon(false))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry_app.appInfo.displayName())
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry_app.appInfo.version() ?? "?")
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(entry_newVersion.version)
                        .foregroundStyle(.blue)
                }
                .font(.system(size: 12))
                if let desc = entry_newVersion.localizedDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                onUpdate()
            } label: {
                if isUpdating {
                    ProgressView().progressViewStyle(.circular)
                        .frame(width: 70, height: 28)
                } else {
                    Text("Update")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
        }
        .padding(.vertical, 6)
    }
}
