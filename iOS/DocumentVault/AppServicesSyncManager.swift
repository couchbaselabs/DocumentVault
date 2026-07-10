import CouchbaseLiteSwift
import Foundation
import Combine

// MARK: - Sync State

struct AppServicesSyncState {
    var isConnected: Bool  = false
    var status: String     = "Disconnected"
    var lastSyncTime: Date? = nil
    var progress: Float    = 0.0
    var documentsCompleted: Int = 0
    var totalDocuments: Int     = 0
    var error: String?     = nil
}

// MARK: - App Services Sync Manager

class AppServicesSyncManager: ObservableObject {

    @Published var syncState = AppServicesSyncState()
    @Published var isEnabled: Bool = false

    private let database: Database
    private var replicator: Replicator?
    private var changeToken: ListenerToken?
    private var isSyncActive = false
    private let syncQueue = DispatchQueue(label: "com.docvault.appsync", qos: .background)

    init(database: Database) {
        self.database = database
        setupReplicator()
    }

    deinit {
        stopSync()
        changeToken?.remove()
    }

    // MARK: - Setup

    private func setupReplicator() {
        guard !AppConfig.syncGatewayURL.contains("your-endpoint"),
              let url = URL(string: AppConfig.syncGatewayURL) else {
            print("⚠️ App Services URL not configured — sync disabled")
            return
        }

        do {
            // Ensure all six collections exist
            var collections: [Collection] = []
            for name in AppConfig.allCollections {
                let col = try database.collection(name: name, scope: AppConfig.scopeName)
                    ?? database.createCollection(name: name, scope: AppConfig.scopeName)
                collections.append(col)
            }

            let target = URLEndpoint(url: url)

            // Build per-collection configs using the non-deprecated init
            let collectionConfigs = collections.map { CollectionConfiguration(collection: $0) }

            var config = ReplicatorConfiguration(collections: collectionConfigs, target: target)
            config.authenticator        = BasicAuthenticator(username: AppConfig.username, password: AppConfig.password)
            config.replicatorType       = .pushAndPull
            config.continuous           = AppConfig.syncContinuous
            config.enableAutoPurge      = false
            config.heartbeat            = TimeInterval(AppConfig.syncHeartbeat)
            config.maxAttempts          = UInt(AppConfig.syncMaxAttempts)
            config.maxAttemptWaitTime   = AppConfig.syncMaxAttemptWaitTime
            config.allowReplicatingInBackground = AppConfig.syncAllowBackground

            replicator = Replicator(config: config)
            changeToken = replicator?.addChangeListener { [weak self] change in
                DispatchQueue.main.async { self?.handleChange(change) }
            }

            print("✅ App Services replicator configured (\(AppConfig.allCollections.count) collections)")
            updateState { $0.status = "Ready to sync" }

        } catch {
            print("❌ Replicator setup failed: \(error)")
            updateState { $0.status = "Setup failed"; $0.error = error.localizedDescription }
        }
    }

    // MARK: - Control

    func enableAppServices() {
        guard !isEnabled else { return }
        isEnabled = true
        startSync()
    }

    func disableAppServices() {
        guard isEnabled else { return }
        isEnabled = false
        stopSync()
        updateState { $0.status = "Sync stopped"; $0.isConnected = false }
    }

    private func startSync() {
        guard let replicator, !isSyncActive else { return }
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.isSyncActive = true
            replicator.start()
            DispatchQueue.main.async { self.updateState { $0.status = "Connecting..." } }
        }
    }

    private func stopSync() {
        guard let replicator, isSyncActive else { return }
        syncQueue.async { [weak self] in
            guard let self else { return }
            replicator.stop()
            self.isSyncActive = false
            DispatchQueue.main.async { self.updateState { $0.isConnected = false } }
        }
    }

    func resetSync() {
        stopSync()
        syncQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.startSync() }
        }
        updateState { $0.status = "Resetting..."; $0.progress = 0; $0.error = nil }
    }

    // MARK: - Change Handling

    private func handleChange(_ change: ReplicatorChange) {
        let status   = change.status
        let progress = status.progress

        updateState { state in
            state.isConnected = (status.activity == .busy || status.activity == .idle)
            if progress.total > 0 {
                state.progress           = Float(progress.completed) / Float(progress.total)
                state.documentsCompleted = Int(progress.completed)
                state.totalDocuments     = Int(progress.total)
            }
            switch status.activity {
            case .connecting: state.status = "Connecting..."
            case .busy:       state.status = "Syncing (\(progress.completed)/\(progress.total))"
            case .idle:       state.status = "Up to date"; state.lastSyncTime = Date(); state.progress = 1.0
            case .stopped:    state.status = "Stopped"; state.isConnected = false; state.progress = 0
            case .offline:    state.status = "Offline"; state.isConnected = false
            @unknown default: state.status = "Unknown"
            }
            if let error = status.error {
                state.error = error.localizedDescription
                state.isConnected = false
                print("❌ Sync error: \(error)")
            } else {
                state.error = nil
            }
        }
    }

    // MARK: - Helper

    private func updateState(_ mutation: (inout AppServicesSyncState) -> Void) {
        var s = syncState
        mutation(&s)
        syncState = s
    }

    var statusSummary: String {
        guard isEnabled else { return "Sync disabled" }
        if let last = syncState.lastSyncTime {
            let f = DateFormatter(); f.timeStyle = .short
            return "\(syncState.status) • \(f.string(from: last))"
        }
        return syncState.status
    }
}
