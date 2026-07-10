// Repurposed: CustodyEvent + CustodyAction + EventVisibility
import Foundation

// MARK: - Custody Action

enum CustodyAction: String, Codable {
    // Capture
    case ingested, emailCaptured, scanned, uploaded
    // Access
    case viewed, downloaded, printed, shared, forwarded
    // Modification
    case annotated, tagAdded, tagRemoved, renamed, moved, statusChanged, versionBumped
    // Access control
    case permissionGranted, permissionRevoked, accessDenied
    // Lifecycle
    case deleted, reprocessed, restored, contentReplaced, deduplicated

    var displayName: String {
        switch self {
        case .ingested:          return "Captured"
        case .emailCaptured:     return "Captured from Email"
        case .scanned:           return "Scanned"
        case .uploaded:          return "Uploaded"
        case .viewed:            return "Viewed"
        case .downloaded:        return "Downloaded"
        case .printed:           return "Printed"
        case .shared:            return "Shared"
        case .forwarded:         return "Forwarded"
        case .annotated:         return "Annotated"
        case .tagAdded:          return "Tag Added"
        case .tagRemoved:        return "Tag Removed"
        case .renamed:           return "Renamed"
        case .moved:             return "Moved"
        case .statusChanged:     return "Status Changed"
        case .versionBumped:     return "New Version"
        case .permissionGranted: return "Access Granted"
        case .permissionRevoked: return "Access Revoked"
        case .accessDenied:      return "Access Denied"
        case .deleted:           return "Deleted"
        case .reprocessed:       return "Reprocessed"
        case .restored:          return "Restored"
        case .contentReplaced:   return "Content Replaced"
        case .deduplicated:      return "Deduplicated"
        }
    }

    var systemImage: String {
        switch self {
        case .ingested, .uploaded:                  return "tray.and.arrow.down"
        case .emailCaptured:                        return "envelope.badge"
        case .scanned:                              return "doc.viewfinder"
        case .viewed:                               return "eye"
        case .downloaded:                           return "arrow.down.circle"
        case .printed:                              return "printer"
        case .shared, .forwarded:                  return "square.and.arrow.up"
        case .annotated:                            return "pencil.and.outline"
        case .tagAdded:                             return "tag"
        case .tagRemoved:                           return "tag.slash"
        case .renamed:                              return "pencil"
        case .moved:                                return "folder"
        case .statusChanged:                        return "arrow.triangle.2.circlepath"
        case .versionBumped:                        return "clock.arrow.circlepath"
        case .permissionGranted:                    return "person.badge.plus"
        case .permissionRevoked:                    return "person.badge.minus"
        case .accessDenied:                         return "lock.shield"
        case .deleted:                              return "trash"
        case .reprocessed:                          return "arrow.clockwise"
        case .restored:                             return "arrow.uturn.backward.circle"
        case .contentReplaced:                      return "doc.on.doc"
        case .deduplicated:                         return "equal.circle"
        }
    }
}

// MARK: - Event Visibility

enum EventVisibility: String, Codable {
    case all       // visible to everyone
    case adminOnly // access events, IPs, device IDs — admin only
}

// MARK: - Custody Event

struct CustodyEvent: Codable, Identifiable, Hashable {
    var id: String
    var timestamp: Date
    var actor: String        // userId or "system" or "email-capture"
    var actorEmail: String?
    var action: CustodyAction
    var deviceId: String?
    var ipAddress: String?   // populated by backend; nil for on-device events
    var notes: String?
    var visibility: EventVisibility
    var metadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        actor: String,
        actorEmail: String? = nil,
        action: CustodyAction,
        deviceId: String? = nil,
        ipAddress: String? = nil,
        notes: String? = nil,
        visibility: EventVisibility = .all,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.actorEmail = actorEmail
        self.action = action
        self.deviceId = deviceId
        self.ipAddress = ipAddress
        self.notes = notes
        self.visibility = visibility
        self.metadata = metadata
    }
}
