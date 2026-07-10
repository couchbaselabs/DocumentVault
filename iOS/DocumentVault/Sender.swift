import Foundation
import CryptoKit

// MARK: - Trust Level

enum TrustLevel: String, Codable, CaseIterable, Comparable {
    case unknown, seen, authorized, verified, blocked

    private static let order: [TrustLevel] = [.blocked, .unknown, .seen, .authorized, .verified]
    static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    var displayName: String {
        switch self {
        case .unknown:    return "Unknown"
        case .seen:       return "Seen"
        case .authorized: return "Authorized"
        case .verified:   return "Verified"
        case .blocked:    return "Blocked"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:    return "questionmark.circle"
        case .seen:       return "eye.circle"
        case .authorized: return "checkmark.shield"
        case .verified:   return "checkmark.seal"
        case .blocked:    return "xmark.shield"
        }
    }

    var color: String {
        switch self {
        case .unknown:    return "gray"
        case .seen:       return "blue"
        case .authorized: return "green"
        case .verified:   return "teal"
        case .blocked:    return "red"
        }
    }
}

// MARK: - Sender

struct Sender: Codable, Identifiable, Hashable {
    var id: String          // "Sender_{SHA256(lowercased email)}"
    var docType: String
    var email: String
    var displayName: String?
    var tenantId: String
    var trustLevel: TrustLevel
    var firstSeenAt: Date
    var lastSeenAt: Date
    var documentCount: Int
    var authorizedBy: String?
    var authorizedAt: Date?
    var notes: String?
    var blockedAt: Date?

    init(email: String, tenantId: String, displayName: String? = nil) {
        self.id = Sender.makeId(from: email)
        self.docType = "Sender"
        self.email = email.lowercased()
        self.displayName = displayName
        self.tenantId = tenantId
        self.trustLevel = .unknown
        self.firstSeenAt = Date()
        self.lastSeenAt = Date()
        self.documentCount = 0
    }

    static func makeId(from email: String) -> String {
        let hash = SHA256.hash(data: Data(email.lowercased().utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        return "Sender_\(hex)"
    }

    var isBlocked: Bool    { trustLevel == .blocked }
    var isTrusted: Bool    { trustLevel == .authorized || trustLevel == .verified }
}
