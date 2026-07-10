import Foundation

// MARK: - Document Thread
// Links multiple documents that originated from the same email thread.

struct DocumentThread: Codable, Identifiable, Hashable {
    var id: String              // "Thread_{gmailThreadId}"
    var docType: String
    var gmailThreadId: String
    var subject: String
    var tenantId: String
    var participantEmails: [String]
    var documentIds: [String]   // ordered by receivedAt
    var firstCapturedAt: Date
    var lastActivityAt: Date
    var custodyChain: [CustodyEvent]

    init(gmailThreadId: String, subject: String, tenantId: String, participantEmails: [String] = []) {
        self.id = "Thread_\(gmailThreadId)"
        self.docType = "DocumentThread"
        self.gmailThreadId = gmailThreadId
        self.subject = subject
        self.tenantId = tenantId
        self.participantEmails = participantEmails
        self.documentIds = []
        self.firstCapturedAt = Date()
        self.lastActivityAt = Date()
        self.custodyChain = []
    }

    static func == (lhs: DocumentThread, rhs: DocumentThread) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
