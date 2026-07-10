import SwiftUI
import CouchbaseLiteSwift
import UIKit
import FoundationModels

@main
struct DocumentVaultApp: App {
    @StateObject private var databaseManager: DatabaseManager
    @StateObject private var authManager: AuthenticationManager

    init() {
        try? Extension.enableVectorSearch()
        let db   = DatabaseManager()
        let auth = AuthenticationManager()
        auth.databaseManager = db
        auth.restoreSessionIfAny()
        _databaseManager = StateObject(wrappedValue: db)
        _authManager     = StateObject(wrappedValue: auth)

        // Migrate boolean field types first (fixes NSNumber-stored booleans from old saves),
        // then run integrity check so dedup works correctly on the fixed data.
        DispatchQueue.global(qos: .userInitiated).async {
            db.migrateDocumentBooleans()
            db.migrateDocumentSchema()
            db.runIntegrityCheck()
            db.reVectorizeUnnormalizedEmbeddings()

            // Kick off NLEmbedding sentence model download in background
            EmbeddingManager.shared.warmup()

            // Foundation Models availability diagnostic
            if #available(iOS 26, *) {
                let model = SystemLanguageModel.default
                switch model.availability {
                case .available:
                    print("🧠 Apple Intelligence: READY — Foundation Models fully loaded")
                case .unavailable(let reason):
                    switch reason {
                    case .deviceNotEligible:
                        print("🧠 Apple Intelligence: UNAVAILABLE — device not eligible")
                    case .appleIntelligenceNotEnabled:
                        print("🧠 Apple Intelligence: UNAVAILABLE — not enabled in Settings → Apple Intelligence & Siri")
                    case .modelNotReady:
                        print("🧠 Apple Intelligence: DOWNLOADING — model assets still loading, check Settings → Apple Intelligence")
                    @unknown default:
                        print("🧠 Apple Intelligence: UNAVAILABLE — reason: \(reason)")
                    }
                @unknown default:
                    print("🧠 Apple Intelligence: UNKNOWN state")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    AuthenticatedContentView()
                        .environmentObject(databaseManager)
                        .environmentObject(authManager)
                } else {
                    LoginView()
                        .environmentObject(authManager)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
            .modifier(MacTextScaleModifier())
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                // Re-check after each foreground return — catches sync-delivered duplicates
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) {
                    databaseManager.migrateDocumentBooleans()
                    databaseManager.migrateDocumentSchema()
                    databaseManager.runIntegrityCheck()
                }
            }
        }
    }
}

struct MacTextScaleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            content
                .dynamicTypeSize(.xLarge ... .xxxLarge)
        } else {
            content
        }
    }
}
