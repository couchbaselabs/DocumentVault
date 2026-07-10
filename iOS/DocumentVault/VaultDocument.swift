// Repurposed: VaultDocument + DocumentSource + EmailMetadata
import Foundation

// MARK: - Document Status

enum DocumentStatus: String, Codable, CaseIterable {
    case draft, review, published, archived, quarantine

    var displayName: String {
        switch self {
        case .draft:      return "Draft"
        case .review:     return "In Review"
        case .published:  return "Published"
        case .archived:   return "Archived"
        case .quarantine: return "Quarantined"
        }
    }

    var systemImage: String {
        switch self {
        case .draft:      return "doc"
        case .review:     return "eye"
        case .published:  return "checkmark.circle"
        case .archived:   return "archivebox"
        case .quarantine: return "exclamationmark.shield"
        }
    }
}

// MARK: - Processing Status

enum ProcessingStatus: String, Codable {
    case pending, extracting, embedding, complete, failed
}

// MARK: - Source Type

enum SourceType: String, Codable {
    case email, camera, filePicker, api, manual
}

// MARK: - Email Metadata

struct EmailMetadata: Codable, Hashable {
    var messageId: String
    var threadId: String
    var subject: String
    var from: String
    var to: [String]
    var cc: [String]
    var receivedAt: Date
    var hasAttachments: Bool
    var attachmentCount: Int
}

// MARK: - Document Source

struct DocumentSource: Codable, Hashable {
    var type: SourceType
    var capturedBy: String
    var capturedAt: Date
    var emailMetadata: EmailMetadata?
}

// MARK: - Vault Document

struct VaultDocument: Codable, Identifiable, Hashable {
    var id: String
    var docType: String
    var name: String
    var fileExtension: String
    var mimeType: String
    var size: Int
    var folderId: String?
    var ownerId: String
    var tenantId: String
    var tags: [String]
    var status: DocumentStatus
    var version: Int
    var contentLocalPath: String?
    var contentRef: String?
    var textContent: String?     // full extracted text — FTS indexed
    var summary: String?         // AI-generated summary — FTS indexed, used for embedding
    var contentCategory: String? // AI-inferred category (legal, financial, medical, etc.)
    var embedding: [Float]?
    var processingStatus: ProcessingStatus
    var ocrProcessed: Bool
    var custodyId: String
    var contentHash: String?
    var source: DocumentSource
    var custodyChain: [CustodyEvent]
    var relatedDocumentIds: [String]
    var isDeleted: Bool
    var deletedAt: Date?
    var hasBlob: Bool
    var createdAt: Date
    var updatedAt: Date
    var client: String?
    var matter: String?
    var author: String?
    var profileDocType: String?
    var searchBoost: Float         // accumulated relevance feedback weight
    var feedbackTags: [String]     // query terms added via "this is the one" feedback

    init(
        id: String = "Doc_\(UUID().uuidString)",
        name: String,
        fileExtension: String,
        mimeType: String,
        size: Int = 0,
        folderId: String? = nil,
        ownerId: String,
        tenantId: String,
        tags: [String] = [],
        status: DocumentStatus = .draft,
        version: Int = 1,
        source: DocumentSource,
        processingStatus: ProcessingStatus = .pending,
        ocrProcessed: Bool = false,
        custodyId: String = UUID().uuidString,
        relatedDocumentIds: [String] = [],
        client: String? = nil,
        matter: String? = nil,
        author: String? = nil,
        profileDocType: String? = nil
    ) {
        self.id = id
        self.docType = "Document"
        self.name = name
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.size = size
        self.folderId = folderId
        self.ownerId = ownerId
        self.tenantId = tenantId
        self.tags = tags
        self.status = status
        self.version = version
        self.source = source
        self.processingStatus = processingStatus
        self.ocrProcessed = ocrProcessed
        self.custodyId = custodyId
        self.contentHash = nil
        self.summary = nil
        self.contentCategory = nil
        self.custodyChain = []
        self.relatedDocumentIds = relatedDocumentIds
        self.isDeleted = false
        self.deletedAt = nil
        self.hasBlob = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.searchBoost = 0.0
        self.feedbackTags = []
        self.client = client
        self.matter = matter
        self.author = author
        self.profileDocType = profileDocType
    }

    static func == (lhs: VaultDocument, rhs: VaultDocument) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayMimeType: String {
        let map: [String: String] = [
            "pdf": "PDF", "doc": "Word", "docx": "Word",
            "xls": "Excel", "xlsx": "Excel", "csv": "CSV",
            "txt": "Text", "jpg": "Image", "jpeg": "Image",
            "png": "Image", "heic": "Image", "tiff": "Image"
        ]
        return map[fileExtension.lowercased()] ?? fileExtension.uppercased()
    }

    var isFromEmail: Bool { source.type == .email }
    var isTrusted: Bool { status != .quarantine }
}
