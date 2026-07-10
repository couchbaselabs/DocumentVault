import SwiftUI

// MARK: - Full Sync Status View (shown in Profile tab)

struct SyncStatusView: View {
    @EnvironmentObject var dbManager: DatabaseManager

    var body: some View {
        let state = dbManager.getAppServicesSyncState()

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: state?.isConnected == true ? "cloud.fill" : "icloud.slash")
                        .foregroundColor(state?.isConnected == true ? .green : .secondary)
                    Text(state?.status ?? "Not configured")
                        .font(.subheadline)
                    Spacer()
                    if dbManager.isAppServicesEnabled {
                        Button("Stop")  { dbManager.disableAppServices() }
                            .font(.caption).buttonStyle(.bordered)
                    } else {
                        Button("Start") { dbManager.enableAppServices() }
                            .font(.caption).buttonStyle(.borderedProminent)
                    }
                }

                if let state, state.totalDocuments > 0 {
                    ProgressView(value: state.progress)
                    Text("\(state.documentsCompleted) / \(state.totalDocuments) documents")
                        .font(.caption).foregroundColor(.secondary)
                }

                if let err = state?.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                }

                if let last = state?.lastSyncTime {
                    Text("Last synced: \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        } label: {
            Label("Capella Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
        }
    }
}

// MARK: - Sync Status Badge (compact, shown in nav bar)

struct SyncStatusBadge: View {
    @EnvironmentObject var dbManager: DatabaseManager

    var body: some View {
        let state = dbManager.getAppServicesSyncState()
        let connected = state?.isConnected ?? false

        Image(systemName: connected ? "cloud.fill" : "icloud.slash")
            .foregroundColor(connected ? .green : .secondary)
            .font(.caption)
    }
}
