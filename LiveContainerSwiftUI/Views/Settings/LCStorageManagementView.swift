import SwiftUI

struct LCStorageManagementView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @StateObject private var model = LCStorageManagementModel()

    var body: some View {
        Form {
            LCStorageSummarySection(
                breakdown: model.breakdown,
                isCalculating: model.isCalculating,
                errorInfo: model.errorInfo
            )
            LCInstalledAppsSection(breakdown: model.breakdown)
        }
        .navigationTitle("lc.settings.storageManagement".loc)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        await model.refresh(apps: sharedModel.apps, hiddenApps: sharedModel.hiddenApps)
    }
}
