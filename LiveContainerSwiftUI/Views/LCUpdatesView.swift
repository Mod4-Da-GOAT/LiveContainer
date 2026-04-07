//
//  LCUpdatesView.swift
//  LiveContainerSwiftUI
//

import SwiftUI

struct LCUpdatesView: View {
    @EnvironmentObject private var sharedModel: SharedModel

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

    @State private var hasAppeared = false
    @State private var isUpdatingAll = false

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
            // Content fills the full page — no Group wrapper
            ZStack {
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
                            app: entry.app,
                            newVersion: entry.newVersion
                        ) {
                            triggerInstall(url: entry.newVersion.downloadURL)
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
                            Task { await sharedModel.sourcesViewModel.refreshAllSources() }
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
                        .disabled(isUpdatingAll || !sharedModel.pendingInstallURLs.isEmpty)
                    }
                }
            }
            .refreshable {
                await sharedModel.sourcesViewModel.refreshAllSources()
            }
            .onAppear {
                // Lazy refresh: fire network fetch only on first appear
                if !hasAppeared {
                    hasAppeared = true
                    Task { await sharedModel.sourcesViewModel.refreshAllSources() }
                }
            }
        }
    }

    private func triggerInstall(url: URL) {
        // Single-app update: switch to apps tab then let LCAppListView handle it
        withAnimation { DataManager.shared.model.selectedTab = .apps }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(
                name: NSNotification.InstallAppNotification,
                object: ["url": url]
            )
        }
    }

    private func updateAll() async {
        let entries = updateEntries
        guard !entries.isEmpty else { return }
        isUpdatingAll = true

        // Push all URLs into the shared queue. LCAppListView's drainInstallQueue
        // will dequeue and await each installFromUrl call sequentially, so only
        // one install dialog runs at a time.
        let urls = entries.map { $0.newVersion.downloadURL }
        await MainActor.run {
            sharedModel.pendingInstallURLs.append(contentsOf: urls)
            // Switch to apps tab so the user can see progress and respond to alerts
            withAnimation { DataManager.shared.model.selectedTab = .apps }
        }

        // Wait until the queue is fully drained before re-enabling the button
        while !sharedModel.pendingInstallURLs.isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        isUpdatingAll = false
    }
}

// MARK: - Row

private struct UpdateRowView: View {
    let app: LCAppModel
    let newVersion: AltStoreSourceAppVersion
    let onUpdate: () -> Void

    @State private var icon: UIImage

    init(app: LCAppModel, newVersion: AltStoreSourceAppVersion, onUpdate: @escaping () -> Void) {
        self.app = app
        self.newVersion = newVersion
        self.onUpdate = onUpdate
        _icon = State(initialValue: app.appInfo.iconIsDarkIcon(false))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.appInfo.displayName())
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(app.appInfo.version() ?? "?")
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(newVersion.version)
                        .foregroundStyle(.blue)
                }
                .font(.system(size: 12))
                if let desc = newVersion.localizedDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onUpdate) {
                Text("Update")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
