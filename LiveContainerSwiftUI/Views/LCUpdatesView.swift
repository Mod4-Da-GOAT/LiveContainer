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
            ScrollView {
                if sharedModel.sourcesViewModel.isRefreshingAll && updateEntries.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Checking for updates…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
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
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    VStack(spacing: 8) {
                        ForEach(updateEntries) { entry in
                            UpdateBannerView(
                                app: entry.app,
                                newVersion: entry.newVersion
                            ) {
                                triggerInstall(url: entry.newVersion.downloadURL)
                            }
                        }
                    }
                    .padding()
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
                if !hasAppeared {
                    hasAppeared = true
                    Task { await sharedModel.sourcesViewModel.refreshAllSources() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func triggerInstall(url: URL) {
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
        let urls = entries.map { $0.newVersion.downloadURL }
        await MainActor.run {
            sharedModel.pendingInstallURLs.append(contentsOf: urls)
            withAnimation { DataManager.shared.model.selectedTab = .apps }
        }
        while !sharedModel.pendingInstallURLs.isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        isUpdatingAll = false
    }
}

// MARK: - Banner row matching LCAppBanner style exactly

private struct UpdateBannerView: View {
    let app: LCAppModel
    let newVersion: AltStoreSourceAppVersion
    let onUpdate: () -> Void

    @AppStorage("dynamicColors", store: LCUtils.appGroupUserDefault) var dynamicColors = true
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false
    @Environment(\.colorScheme) var colorScheme

    @State private var icon: UIImage
    @State private var mainColor: Color

    init(app: LCAppModel, newVersion: AltStoreSourceAppVersion, onUpdate: @escaping () -> Void) {
        self.app = app
        self.newVersion = newVersion
        self.onUpdate = onUpdate
        let img = app.appInfo.iconIsDarkIcon(
            LCUtils.appGroupUserDefault.bool(forKey: "darkModeIcon")
        )
        _icon = State(initialValue: img)
        _mainColor = State(initialValue: Self.extractColor(from: img))
    }

    private var textColor: Color {
        let c = dynamicColors ? mainColor : Color("FontColor")
        return colorScheme == .dark ? c.readableTextColor() : c.readableTextColor()
    }

    var body: some View {
        HStack {
            HStack {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 16, height: 16)))

                VStack(alignment: .leading) {
                    Text(app.appInfo.displayName())
                        .font(.system(size: 16)).bold()
                        .foregroundColor(textColor)

                    // installed version → new version, bundle ID
                    Text("\(app.appInfo.version() ?? "?") → \(newVersion.version)  ·  \(app.appInfo.bundleIdentifier() ?? "")")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)

                    // selected container name
                    if let container = app.uiSelectedContainer {
                        Text(container.name)
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }

                    // release notes if available
                    if let notes = newVersion.localizedDescription, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(textColor.opacity(0.8))
                            .lineLimit(2)
                    }
                }
            }
            .allowsHitTesting(false)

            Spacer()

            // Update button — styled like the Run capsule in LCAppBanner
            Button(action: onUpdate) {
                Text("Update")
                    .bold()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(height: 32)
                    .padding(.horizontal, 16)
                    .minimumScaleFactor(0.1)
            }
            .buttonStyle(.plain)
            .background(
                Capsule().fill(dynamicColors ? mainColor : Color("FontColor"))
            )
            .clipShape(Capsule())
        }
        .padding()
        .frame(minHeight: 88)
        .background {
            RoundedRectangle(cornerSize: CGSize(width: 22, height: 22))
                .fill(dynamicColors ? mainColor.opacity(0.5) : Color("AppBannerBG"))
        }
        .onChange(of: darkModeIcon) { newVal in
            let img = app.appInfo.iconIsDarkIcon(newVal)
            icon = img
            mainColor = Self.extractColor(from: img)
        }
    }

    // Same color extraction logic as LCAppBanner.extractMainHueColor()
    static func extractColor(from image: UIImage) -> Color {
        guard let cgImage = image.cgImage else { return .red }
        var pixelData = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixelData, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .red }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = CGFloat(pixelData[0]) / 255
        let g = CGFloat(pixelData[1]) / 255
        let b = CGFloat(pixelData[2]) / 255
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        if bri < 0.1 && sat < 0.1 { return .red }
        if bri < 0.3 { bri = 0.3 }
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}
