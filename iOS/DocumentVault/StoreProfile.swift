// Repurposed: UserProfile + UserRole + Folder + Annotation
import Foundation

// MARK: - User Role

enum UserRole: String, Codable, CaseIterable {
    case viewer, contributor, admin

    var displayName: String {
        switch self {
        case .viewer:      return "Viewer"
        case .contributor: return "Contributor"
        case .admin:       return "Admin"
        }
    }

    var canEdit: Bool     { self == .contributor || self == .admin }
    var canAdmin: Bool    { self == .admin }
}

// MARK: - User Profile

struct UserProfile: Codable, Identifiable, Hashable {
    var id: String
    var docType: String
    var displayName: String
    var email: String
    var tenantId: String
    var role: UserRole
    var avatarURL: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "Profile_\(UUID().uuidString)",
        displayName: String,
        email: String,
        tenantId: String,
        role: UserRole = .contributor
    ) {
        self.id = id
        self.docType = "UserProfile"
        self.displayName = displayName
        self.email = email
        self.tenantId = tenantId
        self.role = role
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Folder

struct Folder: Codable, Identifiable, Hashable {
    var id: String
    var docType: String
    var name: String
    var parentId: String?
    var ownerId: String
    var tenantId: String
    var color: String?    // hex
    var icon: String?     // SF Symbol name
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "Folder_\(UUID().uuidString)",
        name: String,
        parentId: String? = nil,
        ownerId: String,
        tenantId: String,
        color: String? = nil,
        icon: String? = "folder"
    ) {
        self.id = id
        self.docType = "Folder"
        self.name = name
        self.parentId = parentId
        self.ownerId = ownerId
        self.tenantId = tenantId
        self.color = color
        self.icon = icon ?? "folder"
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func == (lhs: Folder, rhs: Folder) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Annotation

struct Annotation: Codable, Identifiable, Hashable {
    var id: String
    var docType: String
    var documentId: String
    var tenantId: String
    var authorId: String
    var authorEmail: String?
    var body: String
    var page: Int?
    var resolved: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "Ann_\(UUID().uuidString)",
        documentId: String,
        tenantId: String,
        authorId: String,
        authorEmail: String? = nil,
        body: String,
        page: Int? = nil
    ) {
        self.id = id
        self.docType = "Annotation"
        self.documentId = documentId
        self.tenantId = tenantId
        self.authorId = authorId
        self.authorEmail = authorEmail
        self.body = body
        self.page = page
        self.resolved = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
