import Foundation
import UIKit

// MARK: - Custody Service
// Appends CustodyEvents to VaultDocument.custodyChain.
// All appends are additive — events are never deleted or modified.
// adminOnly events (access denied, IP, device ID) are filtered from
// the regular user view in CustodyTimelineView.

struct CustodyService {
    static let shared = CustodyService()
    private init() {}

    // MARK: - Record Event

    func record(
        action: CustodyAction,
        on docId: String,
        actor: String,
        actorEmail: String? = nil,
        notes: String? = nil,
        visibility: EventVisibility = .all,
        metadata: [String: String]? = nil,
        db: DatabaseManager
    ) {
        // Capture main-actor-isolated UIDevice value before entering the Task
        let deviceId = UIDevice.current.identifierForVendor?.uuidString
        Task {
            guard var doc = try? db.fetchDocument(id: docId) else { return }

            let event = CustodyEvent(
                actor: actor,
                actorEmail: actorEmail,
                action: action,
                deviceId: deviceId,
                notes: notes,
                visibility: visibility,
                metadata: metadata
            )

            doc.custodyChain.append(event)
            doc.updatedAt = Date()
            try? db.saveDocument(doc)
        }
    }

    // MARK: - Convenience Wrappers

    func recordViewed(docId: String, actor: String, actorEmail: String? = nil, db: DatabaseManager) {
        record(action: .viewed, on: docId, actor: actor, actorEmail: actorEmail,
               visibility: .adminOnly, db: db)
    }

    func recordAnnotated(docId: String, actor: String, db: DatabaseManager) {
        record(action: .annotated, on: docId, actor: actor, db: db)
    }

    func recordStatusChanged(docId: String, actor: String, to newStatus: DocumentStatus, db: DatabaseManager) {
        record(action: .statusChanged, on: docId, actor: actor,
               notes: "→ \(newStatus.displayName)", db: db)
    }

    func recordTagAdded(docId: String, actor: String, tag: String, db: DatabaseManager) {
        record(action: .tagAdded, on: docId, actor: actor, notes: tag, db: db)
    }

    func recordTagRemoved(docId: String, actor: String, tag: String, db: DatabaseManager) {
        record(action: .tagRemoved, on: docId, actor: actor, notes: tag, db: db)
    }

    func recordMoved(docId: String, actor: String, to folderName: String, db: DatabaseManager) {
        record(action: .moved, on: docId, actor: actor, notes: "→ \(folderName)", db: db)
    }

    func recordShared(docId: String, actor: String, db: DatabaseManager) {
        record(action: .shared, on: docId, actor: actor, db: db)
    }

    func recordAccessDenied(docId: String, attemptedBy: String, db: DatabaseManager) {
        record(action: .accessDenied, on: docId, actor: attemptedBy,
               visibility: .adminOnly, db: db)
    }

    func recordDeleted(docId: String, actor: String, db: DatabaseManager) {
        record(action: .deleted, on: docId, actor: actor, db: db)
    }

    func recordReprocessed(docId: String, actor: String, db: DatabaseManager) {
        record(action: .reprocessed, on: docId, actor: actor, db: db)
    }

    func recordRestored(docId: String, actor: String, notes: String? = nil, db: DatabaseManager) {
        record(action: .restored, on: docId, actor: actor, notes: notes, db: db)
    }

    func recordContentReplaced(docId: String, actor: String, oldHash: String, newHash: String, db: DatabaseManager) {
        record(action: .contentReplaced, on: docId, actor: actor,
               notes: "Hash: \(String(oldHash.prefix(12)))… → \(String(newHash.prefix(12)))…", db: db)
    }

    // MARK: - Filter for Role

    func events(for doc: VaultDocument, isAdmin: Bool) -> [CustodyEvent] {
        if isAdmin { return doc.custodyChain.sorted { $0.timestamp < $1.timestamp } }
        return doc.custodyChain
            .filter { $0.visibility == .all }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
