import Foundation
import CouchbaseLiteSwift
import CryptoKit
import Combine
import UIKit

// MARK: - Notification Names

extension Notification.Name {
    static let vaultDocumentsChanged   = Notification.Name("vaultDocumentsChanged")
    static let vaultFoldersChanged     = Notification.Name("vaultFoldersChanged")
    static let vaultAnnotationsChanged = Notification.Name("vaultAnnotationsChanged")
}

// MARK: - Database Manager

class DatabaseManager: ObservableObject {
    var database: Database?
    private let databaseName = AppConfig.databaseName

    private var changeTokens: [ListenerToken] = []
    private var syncCancellable: AnyCancellable?

    @Published var appServicesSyncManager: AppServicesSyncManager?
    @Published var isAppServicesEnabled: Bool = false

    init() {
        AppConfig.printConfiguration()
        openDatabase()
        setupChangeListeners()
        setupAppServicesIntegration()

        if AppConfig.enableAppServicesSync {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.enableAppServices()
            }
        }
    }

    deinit {
        changeTokens.forEach { $0.remove() }
    }

    func openDatabase() {
        do {
            checkAndHandleTenantChange()
            database = try Database(name: databaseName, config: DatabaseConfiguration())
            print("✅ DocumentVaultDB opened: \(database?.path ?? "?")")
        } catch {
            print("❌ Failed to open database: \(error)")
        }
    }

    func resetDatabase() throws {
        // Disable sync
        appServicesSyncManager?.disableAppServices()
        appServicesSyncManager = nil
        isAppServicesEnabled = false
        
        // Remove change listeners
        changeTokens.forEach { $0.remove() }
        changeTokens.removeAll()
        
        // Close database
        if let db = database {
            try db.close()
        }
        database = nil
        
        // Delete database directory
        try Database.delete(withName: databaseName)
        print("🗑️ Database reset successfully")
        
        // Clear index migration key so vector index is rebuilt
        UserDefaults.standard.removeObject(forKey: "vectorIndexMigrated_centroids8_v2")
        
        // Re-open and rebuild
        openDatabase()
        setupIndexes()
        setupChangeListeners()
        setupAppServicesIntegration()
        
        if AppConfig.enableAppServicesSync {
            enableAppServices()
        }
    }

    private func checkAndHandleTenantChange() {
        let defaults = UserDefaults.standard
        let key = "lastConfiguredTenant"
        let current = AppConfig.currentTenantId
        let last = defaults.string(forKey: key)

        if let last, last != current, !current.isEmpty {
            print("🔄 Tenant changed \(last) → \(current), purging local data")
            try? Database.delete(withName: databaseName)
        }
        if !current.isEmpty { defaults.set(current, forKey: key) }
    }

    // MARK: - Collection Helper

    func collection(named name: String) throws -> Collection {
        guard let db = database else { throw VaultError.databaseUnavailable }
        return try db.collection(name: name, scope: AppConfig.scopeName)
            ?? db.createCollection(name: name, scope: AppConfig.scopeName)
    }

    // MARK: - Index Setup (called once after open)

    func setupIndexes() {
        guard database != nil else { return }
        do {
            let docs = try collection(named: AppConfig.documentsCollection)

            // Full-text search
            let fts = FullTextIndexConfiguration(["name", "textContent", "summary", "tags"])
            try docs.createIndex(withName: "fts_idx", config: fts)

            // Drop the existing vector index so new config (centroids:8, lazy) takes effect.
            // Only do this once per install/upgrade via a UserDefaults migration flag.
            let migratedKey = "vectorIndexMigrated_centroids8_v7"
            if !UserDefaults.standard.bool(forKey: migratedKey) {
                try? docs.deleteIndex(forName: "vector_idx")
                UserDefaults.standard.set(true, forKey: migratedKey)
                print("🔄 Vector index migration: dropped old index for automatic non-lazy vector search")
            }

            var vec = VectorIndexConfiguration(expression: "embedding", dimensions: 1024, centroids: 8)
            vec.metric = .cosine
            vec.isLazy = false
            if (try? docs.createIndex(withName: "vector_idx", config: vec)) != nil {
                print("✅ Vector index created (Cosine metric, automatic indexing, centroids:8, 1024-dim)")
            } else {
                print("⚠️ Vector index skipped — CouchbaseLiteVectorSearch not enabled")
            }

            // Value indexes for common query patterns
            try docs.createIndex(withName: "folder_idx",
                config: ValueIndexConfiguration(["folderId", "status"]))
            try docs.createIndex(withName: "updated_idx",
                config: ValueIndexConfiguration(["updatedAt"]))
            try docs.createIndex(withName: "owner_idx",
                config: ValueIndexConfiguration(["ownerId"]))

            print("✅ Indexes created on documents collection")
        } catch {
            print("⚠️ Index setup: \(error)")
        }

        // Ensure all other collections exist
        for name in AppConfig.allCollections {
            _ = try? collection(named: name)
        }
    }

    // MARK: - Change Listeners

    private func setupChangeListeners() {
        changeTokens.forEach { $0.remove() }
        changeTokens = []
        guard database != nil else { return }

        for colName in [AppConfig.documentsCollection, AppConfig.foldersCollection, AppConfig.annotationsCollection] {
            guard let col = try? collection(named: colName) else { continue }
            let notif: Notification.Name
            if colName == AppConfig.documentsCollection {
                notif = .vaultDocumentsChanged
            } else if colName == AppConfig.foldersCollection {
                notif = .vaultFoldersChanged
            } else {
                notif = .vaultAnnotationsChanged
            }
            let token = col.addChangeListener { [weak self] change in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                    NotificationCenter.default.post(name: notif, object: nil)
                    
                    if colName == AppConfig.annotationsCollection {
                        self?.handleAnnotationsChanged(change.documentIDs)
                    }
                }
            }
            changeTokens.append(token)
        }
        print("✅ Change listeners configured")
    }

    private func handleAnnotationsChanged(_ documentIDs: [String]) {
        guard let col = try? collection(named: AppConfig.annotationsCollection) else { return }
        
        var docIdsToReembed = Set<String>()
        for annId in documentIDs {
            if let raw = try? col.document(id: annId),
               let docId = raw.string(forKey: "documentId") {
                docIdsToReembed.insert(docId)
            }
        }
        
        for docId in docIdsToReembed {
            print("🔔 Sync'd annotation for \(docId) -> triggering background re-vectorization")
            Task {
                await DocumentProcessingPipeline.shared.retryProcessing(for: docId, db: self)
            }
        }
    }

    func simulateIncomingEmail() async throws {
        let tenant = AppConfig.currentTenantId.isEmpty ? "acme-corp" : AppConfig.currentTenantId
        let scope = AppConfig.scopeName
        let docColl = AppConfig.documentsCollection
        
        // 1. Locate the target case matter document (e.g. PwC Tax Return)
        var targetDocId = "Doc_IRS_Form_1120_2025"
        if let docs = try? collection(named: docColl),
           (try? docs.document(id: targetDocId)) == nil {
            let sql = "SELECT META().id FROM `\(scope)`.`\(docColl)` WHERE matter LIKE '%Corporate Tax%' OR matter LIKE '%AN-01%' LIMIT 1"
            if let query = try? database?.createQuery(sql),
               let results = try? query.execute(),
               let first = results.next(),
               let id = first.string(at: 0) {
                targetDocId = id
            }
        }
        
        guard let docsCol = try? collection(named: docColl),
              let targetRaw = try? docsCol.document(id: targetDocId),
              let targetDoc = try? decodeDocument(from: targetRaw) else {
            throw NSError(domain: "DatabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target case matter document (Corporate Tax T01) not found in database. Please run the seeder first."])
        }
        
        let emailDocId = "Doc_Email_Jane_\(UUID().uuidString.prefix(8).lowercased())"
        let emailSubject = "PwC Negligence - Critical Update on Matter AN-01"
        let emailSender = "jane.doe@acme-corp.com"
        let emailBody = """
        From: \(emailSender)
        To: legal-team@acme-corp.com
        Subject: \(emailSubject)
        Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))

        Dear team,
        I have received the latest tax filings and compared them with PwC's statements on corporate tax disclosures. 
        There is a significant discrepancy showing that PwC failed to disclose over $15M in deferred tax liabilities for FY2025. 
        This confirms clear negligence in their audit oversight and tax preparation on Matter AN-01.
        We need to update our brief immediately to reflect this negligence and the new liability exposure.
        
        Best regards,
        Jane
        """
        
        // 2. Create the email document
        let metadata = EmailMetadata(
            messageId: "<msg-jane-pwc-\(UUID().uuidString.prefix(6).lowercased())@acme-corp.com>",
            threadId: "thread-pwc-tax-01",
            subject: emailSubject,
            from: emailSender,
            to: ["legal-team@acme-corp.com"],
            cc: [],
            receivedAt: Date(),
            hasAttachments: false,
            attachmentCount: 0
        )
        
        var emailDoc = VaultDocument(
            id: emailDocId,
            name: "Jane - PwC Corporate Tax Negligence.eml",
            fileExtension: "eml",
            mimeType: "message/rfc822",
            size: emailBody.count,
            folderId: targetDoc.folderId,
            ownerId: emailSender,
            tenantId: tenant,
            tags: ["email", "jane", "pwc", "corporate-tax", "negligence", "critical"],
            status: .published,
            version: 1,
            source: DocumentSource(type: .email, capturedBy: emailSender, capturedAt: Date(), emailMetadata: metadata)
        )
        emailDoc.textContent = emailBody
        emailDoc.summary = "Email from Jane Doe notifying the legal team of critical deferred tax liability disclosure errors by PwC, confirming audit oversight negligence on Matter AN-01."
        emailDoc.contentCategory = "financial"
        emailDoc.hasBlob = true
        emailDoc.client = targetDoc.client
        emailDoc.matter = targetDoc.matter
        emailDoc.author = "Jane Doe"
        emailDoc.profileDocType = "Incoming Email"
        
        emailDoc.custodyChain = [
            CustodyEvent(
                actor: emailSender,
                actorEmail: emailSender,
                action: .emailCaptured,
                deviceId: "MailServer_Sync_01",
                notes: "Automatically captured from Jane's corporate inbox."
            )
        ]
        
        let emailTextForEmbedding = "\(emailDoc.name) \(emailDoc.summary ?? "") \(emailDoc.textContent ?? "")"
        if let embedding = await EmbeddingManager.shared.generateTextEmbedding(from: emailTextForEmbedding) {
            emailDoc.embedding = embedding
        }
        
        let fileData = emailBody.data(using: .utf8) ?? Data()
        if let localPath = try? await ContentStorageService.shared.save(data: fileData, for: emailDocId, extension: "eml") {
            emailDoc.contentLocalPath = localPath
        }
        
        try saveDocument(emailDoc)
        let blob = Blob(contentType: "message/rfc822", data: fileData)
        try? attachBlob(blob, toDocumentId: emailDocId)
        
        // 3. Add custody event & Annotation to target case matter document to trigger re-vectorization
        var updatedTarget = targetDoc
        updatedTarget.custodyChain.append(
            CustodyEvent(
                actor: emailSender,
                actorEmail: emailSender,
                action: .emailCaptured,
                notes: "Linked email update from Jane regarding PwC negligence on Matter AN-01."
            )
        )
        try saveDocument(updatedTarget)
        
        let annotationId = "Ann_Email_Jane_PWC_negligence_\(UUID().uuidString.prefix(8).lowercased())"
        let annotation = Annotation(
            id: annotationId,
            documentId: targetDocId,
            tenantId: tenant,
            authorId: emailSender,
            authorEmail: emailSender,
            body: "New Email captured from Jane Doe: PwC Negligence - Critical Update on Matter AN-01. Found PwC failed to disclose over $15M in deferred tax liabilities for FY2025.",
            page: nil
        )
        try saveAnnotation(annotation)
        
        NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
    }

    // MARK: - Document CRUD

    func saveDocument(_ doc: VaultDocument) throws {
        let col = try collection(named: AppConfig.documentsCollection)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(doc)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VaultError.encodingFailed
        }
        let mutable = MutableDocument(id: doc.id, data: dict)
        // CBL stores NSNumber-wrapped booleans (from JSON round-trip) as numbers,
        // which breaks `= true` queries. Re-set booleans explicitly via CBL's typed API.
        mutable.setBoolean(doc.isDeleted,    forKey: "isDeleted")
        mutable.setBoolean(doc.ocrProcessed, forKey: "ocrProcessed")
        // Re-attach existing blob and derive hasBlob from ACTUAL CBL state,
        // not the struct field (which can be stale if attachBlob ran after the struct was created).
        if let existing = try? col.document(id: doc.id),
           let blob = existing.blob(forKey: "fileBlob") {
            mutable.setBlob(blob, forKey: "fileBlob")
            mutable.setBoolean(true, forKey: "hasBlob")   // blob is present → always true
        } else {
            mutable.setBoolean(doc.hasBlob, forKey: "hasBlob")   // no blob in CBL
        }
        try col.save(document: mutable)
    }

    func fetchDocument(id: String) throws -> VaultDocument? {
        let col = try collection(named: AppConfig.documentsCollection)
        guard let raw = try col.document(id: id) else { return nil }
        return try decodeDocument(from: raw)
    }

    func fetchDocuments(inFolder folderId: String?) throws -> [VaultDocument] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection

        let sql: String
        if let fid = folderId {
            sql = """
            SELECT META().id, *
            FROM `\(scope)`.`\(coll)`
            WHERE folderId = '\(fid)'
              AND (isDeleted IS NOT VALUED OR isDeleted = false)
            ORDER BY updatedAt DESC
            """
        } else {
            sql = """
            SELECT META().id, *
            FROM `\(scope)`.`\(coll)`
            WHERE (folderId IS NOT VALUED OR folderId = '')
              AND (isDeleted IS NOT VALUED OR isDeleted = false)
            ORDER BY updatedAt DESC
            """
        }

        let query = try db.createQuery(sql)
        return try executeDocumentQuery(query)
    }

    func fetchAllDocuments() throws -> [VaultDocument] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection
        let sql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE (isDeleted IS NOT VALUED OR isDeleted = false)
        ORDER BY updatedAt DESC
        """
        let query = try db.createQuery(sql)
        return try executeDocumentQuery(query)
    }

    func fetchDeletedDocuments() throws -> [VaultDocument] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection
        let sql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE isDeleted = true
        ORDER BY deletedAt DESC
        """
        let query = try db.createQuery(sql)
        return try executeDocumentQuery(query)
    }

    /// Finds a non-deleted document by hash.
    func findDocument(byHash hash: String) throws -> VaultDocument? {
        guard let db = database else { return nil }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection
        let sql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE contentHash = '\(hash)'
          AND (isDeleted IS NOT VALUED OR isDeleted = false)
        LIMIT 1
        """
        return try executeDocumentQuery(try db.createQuery(sql)).first
    }

    /// Finds a deleted document by hash — used to offer restoration on re-upload.
    func findDeletedDocument(byHash hash: String) throws -> VaultDocument? {
        guard let db = database else { return nil }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection
        let sql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE contentHash = '\(hash)'
          AND isDeleted = true
        LIMIT 1
        """
        return try executeDocumentQuery(try db.createQuery(sql)).first
    }

    /// Restores a soft-deleted document: clears deletion flags, bumps version, appends custody event.
    func restoreDocument(id: String, actor: String) throws {
        guard var doc = try fetchDocument(id: id) else { throw VaultError.documentNotFound(id) }
        guard doc.isDeleted else { return }
        doc.isDeleted  = false
        doc.deletedAt  = nil
        doc.version   += 1
        doc.updatedAt  = Date()
        doc.custodyChain.append(CustodyEvent(
            actor: actor,
            action: .restored,
            notes: "Restored to v\(doc.version)"
        ))
        try saveDocument(doc)
        NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
    }

    func deleteDocument(id: String) throws {
        let col = try collection(named: AppConfig.documentsCollection)
        guard let doc = try col.document(id: id) else { return }
        try col.delete(document: doc)
    }

    /// Soft-deletes: marks isDeleted=true, records custody, keeps document as historical stub.
    func deleteDocument(id: String, actor: String) throws {
        guard var doc = try fetchDocument(id: id) else { return }
        CustodyService.shared.recordDeleted(docId: id, actor: actor, db: self)
        doc.isDeleted = true
        doc.deletedAt = Date()
        doc.updatedAt = Date()
        try saveDocument(doc)
    }

    // MARK: - Folder CRUD

    func saveFolder(_ folder: Folder) throws {
        let col = try collection(named: AppConfig.foldersCollection)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(folder)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VaultError.encodingFailed
        }
        let mutable = MutableDocument(id: folder.id, data: dict)
        try col.save(document: mutable)
    }

    func fetchAllFolders() throws -> [Folder] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.foldersCollection
        let sql = "SELECT META().id, * FROM `\(scope)`.`\(coll)` ORDER BY name"
        let query = try db.createQuery(sql)
        let results = try query.execute()
        var folders: [Folder] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for result in results {
            guard let dict = result.dictionary(at: 1)?.toDictionary(),
                  let data = try? JSONSerialization.data(withJSONObject: dict) else { continue }
            if let folder = try? decoder.decode(Folder.self, from: data) { folders.append(folder) }
        }
        return folders
    }

    func fetchFolders(parentId: String? = nil) throws -> [Folder] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.foldersCollection

        let sql: String
        if let pid = parentId {
            sql = "SELECT META().id, * FROM `\(scope)`.`\(coll)` WHERE parentId = '\(pid)' ORDER BY name"
        } else {
            sql = "SELECT META().id, * FROM `\(scope)`.`\(coll)` WHERE parentId IS NOT VALUED OR parentId = '' ORDER BY name"
        }

        let query = try db.createQuery(sql)
        let results = try query.execute()
        var folders: [Folder] = []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for result in results {
            guard let dict = result.dictionary(at: 1)?.toDictionary(),
                  let data = try? JSONSerialization.data(withJSONObject: dict) else { continue }
            if let folder = try? decoder.decode(Folder.self, from: data) { folders.append(folder) }
        }
        return folders
    }

    func deleteFolder(id: String) throws {
        let col = try collection(named: AppConfig.foldersCollection)
        guard let doc = try col.document(id: id) else { return }
        try col.delete(document: doc)
    }

    // MARK: - Metadata Queries

    func fetchRecentlyModified(folderId: String? = nil, limit: Int = 5) throws -> [VaultDocument] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection
        var filter = "(isDeleted IS NOT VALUED OR isDeleted = false)"
        if let fid = folderId {
            filter += " AND folderId = '\(fid)'"
        }
        let sql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE \(filter)
        ORDER BY updatedAt DESC
        LIMIT \(limit)
        """
        let query = try db.createQuery(sql)
        return try executeDocumentQuery(query)
    }

    // MARK: - Full-Text Search

    func searchDocuments(query: String, folderId: String? = nil) throws -> [VaultDocument] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection

        // Split into individual tokens and join for FTS so multi-word queries work.
        // Plain space separation is extremely stable in SQLite FTS.
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let ftsExpr = tokens.joined(separator: " ")

        // 1. FTS query — no isDeleted filter; UI groups results by deleted/metadata/full
        var ftsFilter = "MATCH(\(coll).fts_idx, $ftsExpr)"
        if let fid = folderId { ftsFilter += " AND folderId = '\(fid)'" }
        let ftsSql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE \(ftsFilter)
        LIMIT 50
        """
        var results: [VaultDocument] = []
        do {
            let ftsQ = try db.createQuery(ftsSql)
            let ftsParams = Parameters()
            ftsParams.setString(ftsExpr, forName: "ftsExpr")
            ftsQ.parameters = ftsParams
            results = try executeDocumentQuery(ftsQ)
        } catch {
            print("⚠️ FTS query failed: \(error)")
        }
        let ftsIds = Set(results.map { $0.id })

        // 2. LIKE fallback — no isDeleted filter; UI handles grouping
        let escaped = query.replacingOccurrences(of: "'", with: "''")
        var likeFilter = "LOWER(name) LIKE '%\(escaped.lowercased())%'"
        if let fid = folderId { likeFilter += " AND folderId = '\(fid)'" }
        let likeSql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        WHERE \(likeFilter)
        LIMIT 25
        """
        do {
            let likeQ = try db.createQuery(likeSql)
            let likeResults = try executeDocumentQuery(likeQ)
            for doc in likeResults where !ftsIds.contains(doc.id) {
                results.append(doc)
            }
        } catch {
            print("⚠️ LIKE query failed: \(error)")
        }

        return results
    }

    // MARK: - Vector Search

    /// Relative distance cutoff: drop results whose distance exceeds the closest result by this factor.
    /// e.g. 1.5 = drop anything 50% farther than the nearest match. Handles un-normalized vectors.
    private let semanticRelativeCutoff: Double = 1.5

    func semanticSearch(embedding: [Float], folderId: String? = nil, limit: Int = 20) throws -> [VaultDocument] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.documentsCollection

        NSLog("🔍 [DatabaseManager] --- START SEMANTIC SEARCH ---")
        NSLog("🔍 [DatabaseManager] Query embedding count: %d", embedding.count)

        // Diagnostic: how many docs have embeddings?
        var diagFilter = "WHERE embedding IS VALUED"
        if let fid = folderId { diagFilter += " AND folderId = '\(fid)'" }
        if let countQ = try? db.createQuery("""
            SELECT COUNT(*) AS n FROM `\(scope)`.`\(coll)`
            \(diagFilter)
            """),
           let row = try? countQ.execute().next() {
            let n = row.int(forKey: "n")
            NSLog("🔍 [DatabaseManager] Docs in DB with embeddings: %d", n)
        }

        // No isDeleted filter — UI groups results by deleted/metadata/full
        var semFilter = "WHERE embedding IS VALUED"
        if let fid = folderId { semFilter += " AND folderId = '\(fid)'" }
        let sql = """
        SELECT META().id, *
        FROM `\(scope)`.`\(coll)`
        \(semFilter)
        ORDER BY APPROX_VECTOR_DISTANCE(embedding, $vec, 'cosine')
        LIMIT \(limit)
        """
        let q = try db.createQuery(sql)
        let params = Parameters()
        params.setValue(embedding, forName: "vec")
        q.parameters = params

        let all = try executeDocumentQueryWithDistances(q, queryEmbedding: embedding)
        NSLog("🔍 [DatabaseManager] Semantic raw results count: %d", all.count)
        for pair in all {
            NSLog("🔍 [DatabaseManager]   - %@ (id=%@) dist=%.4f", pair.doc.name, pair.doc.id, pair.distance)
        }

        // Use a relative cutoff: drop results much farther than the closest match.
        // Absolute thresholds don't work until vectors are normalized.
        guard let closest = all.first?.distance else {
            NSLog("🔍 [DatabaseManager] No raw results returned, returning empty list")
            return []
        }
        let filtered = all.filter { $0.distance <= closest * semanticRelativeCutoff }.map { $0.doc }
        NSLog("🔍 [DatabaseManager] Closest distance: %.4f, Filtered results count: %d", closest, filtered.count)
        return filtered
    }

    // MARK: - Hybrid Search (RRF + Rocchio)

    // Session-level relevance feedback: query fingerprint → relevant doc IDs
    private var sessionFeedback: [String: [String]] = [:]

    /// Combines FTS and vector retrieval via Reciprocal Rank Fusion, then applies
    /// persistent boost scores and session-level Rocchio query adjustment.
    func hybridSearch(query: String, queryEmbedding: [Float]?, folderId: String? = nil, limit: Int = 20) throws -> [VaultDocument] {
        let queryKey = query.lowercased().trimmingCharacters(in: .whitespaces)

        // Rocchio: adjust query vector toward docs marked relevant this session
        var adjustedEmbedding = queryEmbedding
        if let emb = queryEmbedding,
           let relevantIds = sessionFeedback[queryKey], !relevantIds.isEmpty {
            adjustedEmbedding = rocchioAdjust(query: emb, relevantDocIds: Array(relevantIds))
        }

        // Retrieve from both channels
        let ftsResults = (try? searchDocuments(query: query, folderId: folderId)) ?? []
        var vecResults: [VaultDocument] = []
        if let emb = adjustedEmbedding {
            do {
                vecResults = try semanticSearch(embedding: emb, folderId: folderId, limit: limit * 2)
            } catch {
                print("❌ Semantic search query failed: \(error.localizedDescription)")
            }
        }

        // RRF: score = Σ 1/(k + rank) across each result list
        let k: Double = 60
        var scores: [String: Double] = [:]
        var docMap: [String: VaultDocument] = [:]

        for (rank, doc) in ftsResults.enumerated() {
            scores[doc.id, default: 0] += 1.0 / (k + Double(rank + 1))
            docMap[doc.id] = doc
        }
        for (rank, doc) in vecResults.enumerated() {
            scores[doc.id, default: 0] += 1.0 / (k + Double(rank + 1))
            docMap[doc.id] = doc
        }

        // Add persistent boost from relevance feedback
        for (id, doc) in docMap where doc.searchBoost > 0 {
            scores[id, default: 0] += Double(doc.searchBoost)
        }

        let ranked = scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { docMap[$0.key] }

        print("🔀 Hybrid search '\(query)': fts=\(ftsResults.count) vec=\(vecResults.count) merged=\(ranked.count)")
        return ranked
    }

    /// Rocchio adjustment: shift query vector toward the centroid of relevant docs.
    /// alpha=0.7 keeps most of the original query, beta=0.3 pulls toward relevant docs.
    private func rocchioAdjust(query: [Float], relevantDocIds: [String]) -> [Float] {
        let col = try? collection(named: AppConfig.documentsCollection)
        var relevantVecs: [[Float]] = []
        for docId in relevantDocIds {
            guard let raw = try? col?.document(id: docId),
                  let arr = raw.array(forKey: "embedding")?.toArray() as? [Any] else { continue }
            let vec = arr.compactMap { $0 as? Double }.map { Float($0) }
            if vec.count == query.count { relevantVecs.append(vec) }
        }
        guard !relevantVecs.isEmpty else { return query }

        let alpha: Float = 0.7
        let beta:  Float = 0.3
        let dim = query.count
        var centroid = [Float](repeating: 0, count: dim)
        for vec in relevantVecs {
            for i in 0..<dim { centroid[i] += vec[i] }
        }
        let n = Float(relevantVecs.count)
        centroid = centroid.map { $0 / n }

        var adjusted = [Float](repeating: 0, count: dim)
        for i in 0..<dim { adjusted[i] = alpha * query[i] + beta * centroid[i] }
        return EmbeddingManager.l2Normalize(adjusted)
    }

    /// Marks a document as relevant for a query.
    /// - Updates session Rocchio state immediately (affects current search session).
    /// - Increments persistent searchBoost and merges query tokens into feedbackTags + tags.
    /// - Triggers re-embedding so the doc's vector moves toward this query's neighborhood.
    func markDocumentRelevant(_ docId: String, forQuery query: String) async {
        let queryKey = query.lowercased().trimmingCharacters(in: .whitespaces)

        // Session state for Rocchio
        if sessionFeedback[queryKey] == nil { sessionFeedback[queryKey] = [] }
        if !sessionFeedback[queryKey]!.contains(docId) {
            sessionFeedback[queryKey]!.append(docId)
        }

        // Persistent: boost score + feedback tags
        guard var doc = try? fetchDocument(id: docId) else { return }
        doc.searchBoost = min(doc.searchBoost + 0.15, 1.0)

        let newTokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !doc.feedbackTags.contains($0) }
        doc.feedbackTags.append(contentsOf: newTokens)
        doc.tags = Array(Set(doc.tags + newTokens))
        try? saveDocument(doc)

        // Re-embed with enriched tags so the vector shifts toward this query
        await DocumentProcessingPipeline.shared.retryProcessing(for: docId, db: self)
        print("👍 Marked relevant: '\(doc.name)' for query '\(query)' boost=\(doc.searchBoost)")
    }

    // MARK: - Private Helpers

    private func executeDocumentQuery(_ query: Query) throws -> [VaultDocument] {
        let results = try query.execute()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var docs: [VaultDocument] = []

        for result in results {
            guard let dict = result.dictionary(at: 1)?.toDictionary() else { continue }
            let prepared = injectDocumentDefaults(stripNonJSON(from: dict))
            guard let data = try? JSONSerialization.data(withJSONObject: prepared) else { continue }
            if let doc = try? decoder.decode(VaultDocument.self, from: data) { docs.append(doc) }
        }
        return docs
    }

    private func executeDocumentQueryWithDistances(_ query: Query, queryEmbedding: [Float]) throws -> [(doc: VaultDocument, distance: Double)] {
        NSLog("🔍 [DatabaseManager] Executing document query with distances...")
        let results: ResultSet
        do {
            results = try query.execute()
        } catch {
            NSLog("🔍 [DatabaseManager] ❌ query.execute() failed: %@", error.localizedDescription)
            throw error
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var pairs: [(VaultDocument, Double)] = []

        var count = 0
        for result in results {
            count += 1
            guard let dict = result.dictionary(at: 1)?.toDictionary() else {
                NSLog("🔍 [DatabaseManager]   ⚠️ Row %d: result.dictionary(at: 1) is nil!", count)
                continue
            }
            let prepared = injectDocumentDefaults(stripNonJSON(from: dict))
            guard let data = try? JSONSerialization.data(withJSONObject: prepared) else {
                NSLog("🔍 [DatabaseManager]   ⚠️ Row %d: JSON serialization failed", count)
                continue
            }
            do {
                let doc = try decoder.decode(VaultDocument.self, from: data)
                let distance: Double
                if let emb = doc.embedding {
                    distance = 1.0 - cosineSimilarity(emb, queryEmbedding)
                } else {
                    distance = 1.0
                }
                pairs.append((doc, distance))
            } catch {
                NSLog("🔍 [DatabaseManager]   ❌ Row %d decoding failed: %@", count, error.localizedDescription)
            }
        }
        NSLog("🔍 [DatabaseManager] Query execution complete. Processed %d rows, successfully decoded %d docs.", count, pairs.count)
        return pairs
    }

    private func decodeDocument(from raw: Document) throws -> VaultDocument {
        let prepared = injectDocumentDefaults(stripNonJSON(from: raw.toDictionary()))
        let data = try JSONSerialization.data(withJSONObject: prepared)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VaultDocument.self, from: data)
    }

    /// Supplies default values for fields added after initial release so older stored
    /// documents decode successfully without a full custom Codable init.
    private func injectDocumentDefaults(_ dict: [String: Any]) -> [String: Any] {
        var d = dict
        if d["searchBoost"]   == nil { d["searchBoost"]   = Float(0.0) }
        if d["feedbackTags"]  == nil { d["feedbackTags"]  = [String]() }
        return d
    }

    /// Removes CBL Blob values (and any other non-JSON-serializable types) from a dictionary.
    private func stripNonJSON(from dict: [String: Any]) -> [String: Any] {
        dict.compactMapValues { value -> Any? in
            if value is Blob { return nil }
            if let nested = value as? [String: Any] { return stripNonJSON(from: nested) }
            return value
        }
    }

    // MARK: - Re-vectorization

    /// Re-embeds all documents whose stored embedding is not yet unit-normalized.
    /// Detects un-normalized vectors by checking if L2 magnitude differs significantly from 1.0.
    /// Safe to call on every launch — skips docs that are already normalized.
    func reVectorizeUnnormalizedEmbeddings() {
        Task {
            guard let db = database,
                  let col = try? collection(named: AppConfig.documentsCollection),
                  let q = try? db.createQuery("""
                      SELECT META().id FROM `\(AppConfig.scopeName)`.`\(AppConfig.documentsCollection)`
                      WHERE embedding IS VALUED
                        AND (isDeleted IS NOT VALUED OR isDeleted = false)
                      """),
                  let rows = try? q.execute() else { return }

            var reembedded = 0
            for row in rows {
                guard let docId = row.string(at: 0),
                      let raw = try? col.document(id: docId),
                      let storedVec = raw.array(forKey: "embedding")?.toArray() as? [Any] else { continue }

                // Check dimensions AND normalization — both must be correct
                let floats = storedVec.compactMap { $0 as? Double }.map { Float($0) }
                let correctDims = floats.count == 1024
                let mag = sqrt(floats.reduce(0) { $0 + $1 * $1 })
                let isNormalized = abs(mag - 1.0) < 0.01

                if correctDims && isNormalized { continue }  // already good

                if !correctDims {
                    print("🔄 Dimension mismatch for \(docId): \(floats.count) dims — clearing and re-embedding")
                    writeLog("🔄 Dimension mismatch for \(docId): \(floats.count) dims — clearing and re-embedding")
                    // Clear the bad embedding so the pipeline is forced to regenerate
                    let mut = raw.toMutable()
                    mut.setArray(nil, forKey: "embedding")
                    try? col.save(document: mut)
                }

                // Re-embed via pipeline
                await DocumentProcessingPipeline.shared.retryProcessing(for: docId, db: self)
                reembedded += 1
            }
            if reembedded > 0 {
                print("🔄 Re-vectorized \(reembedded) docs with un-normalized embeddings")
            }
        }
    }

    // MARK: - Integrity Check

    /// Deduplicates the document corpus by SHA-256 hash and fixes stale hasBlob flags.
    /// Safe to call on every launch — no-ops if nothing is wrong.
    @discardableResult
    func runIntegrityCheck() -> (deduplicated: Int, blobFlagsFixed: Int) {
        var deduplicated = 0
        var blobFlagsFixed = 0

        // 1. Deduplicate by contentHash
        if let database = database,
           let query = try? database.createQuery("""
               SELECT META().id, *
               FROM `\(AppConfig.scopeName)`.`\(AppConfig.documentsCollection)`
               WHERE contentHash IS VALUED
                 AND (isDeleted IS NOT VALUED OR isDeleted = false)
               ORDER BY createdAt ASC
               """),
           let allDocs = try? executeDocumentQuery(query) {

            // Group by hash in Swift — avoids any SQL aggregate compatibility concerns
            var byHash: [String: [VaultDocument]] = [:]
            for doc in allDocs {
                guard let hash = doc.contentHash else { continue }
                byHash[hash, default: []].append(doc)
            }

            for (_, group) in byHash where group.count > 1 {
                // Oldest document is canonical; newer ones are duplicates
                let sorted    = group.sorted { $0.createdAt < $1.createdAt }
                var canonical = sorted[0]
                let dupes     = sorted.dropFirst()

                // Merge all custody events from duplicates into canonical
                var merged = canonical.custodyChain
                for dup in dupes { merged += dup.custodyChain }
                merged.sort { $0.timestamp < $1.timestamp }
                merged.append(CustodyEvent(
                    actor: "system",
                    action: .deduplicated,
                    notes: "\(dupes.count) duplicate(s) merged on integrity check"
                ))
                canonical.custodyChain = merged
                canonical.updatedAt    = Date()
                try? saveDocument(canonical)

                // Soft-delete each duplicate, preserving its own custody note
                for var dup in dupes {
                    dup.isDeleted = true
                    dup.deletedAt = Date()
                    dup.custodyChain.append(CustodyEvent(
                        actor: "system",
                        action: .deduplicated,
                        notes: "Duplicate of canonical \(canonical.id) — merged and removed"
                    ))
                    try? saveDocument(dup)
                    deduplicated += 1
                    print("🔧 Integrity: merged duplicate \(dup.id) → canonical \(canonical.id)")
                }
            }
        }

        // 2. Fix stale hasBlob flags
        if let col = try? collection(named: AppConfig.documentsCollection),
           let database = database,
           let query = try? database.createQuery("""
               SELECT META().id, *
               FROM `\(AppConfig.scopeName)`.`\(AppConfig.documentsCollection)`
               WHERE (isDeleted IS NOT VALUED OR isDeleted = false)
               """),
           let docs = try? executeDocumentQuery(query) {

            for var doc in docs {
                guard let raw = try? col.document(id: doc.id) else { continue }
                let blobExists = raw.blob(forKey: "fileBlob") != nil
                if doc.hasBlob != blobExists {
                    doc.hasBlob   = blobExists
                    doc.updatedAt = Date()
                    try? saveDocument(doc)
                    blobFlagsFixed += 1
                    print("🔧 Integrity: fixed hasBlob=\(blobExists) on \(doc.id)")
                }
            }
        }

        if deduplicated > 0 || blobFlagsFixed > 0 {
            print("✅ Integrity check complete — \(deduplicated) deduplicated, \(blobFlagsFixed) blob flags fixed")
            NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
        }

        return (deduplicated, blobFlagsFixed)
    }

    // MARK: - Boolean Migration

    /// Fixes boolean fields (isDeleted, hasBlob, ocrProcessed) that were stored as NSNumber
    /// via the JSON-dict path instead of CBL's typed setBoolean API.
    /// Idempotent — safe to call on every launch. Run this BEFORE runIntegrityCheck.
    func migrateDocumentBooleans() {
        // DIAGNOSTIC VECTOR QUERY
        if let db = database {
            do {
                let sql = """
                SELECT META().id, *
                FROM `\(AppConfig.scopeName)`.`\(AppConfig.documentsCollection)`
                WHERE embedding IS VALUED
                ORDER BY APPROX_VECTOR_DISTANCE(embedding, $vec, 'cosine')
                LIMIT 3
                """
                let q = try db.createQuery(sql)
                let params = Parameters()
                let mockVec = Array(repeating: Float(0.01), count: 1024)
                params.setValue(mockVec, forName: "vec")
                q.parameters = params
                
                let rows = try q.execute()
                NSLog("🔍 [DatabaseManager] 🧪 DIAGNOSTIC: Vector search query executed successfully")
                var rowCount = 0
                for row in rows {
                    rowCount += 1
                    NSLog("🔍 [DatabaseManager] 🧪 Row %d Keys: %@", rowCount, row.keys.joined(separator: ", "))
                    for key in row.keys {
                        if let dict = row.dictionary(forKey: key) {
                            NSLog("🔍 [DatabaseManager]   🧪 Column '%@' is a Dictionary with keys: %@", key, dict.keys.joined(separator: ", "))
                        } else {
                            NSLog("🔍 [DatabaseManager]   🧪 Column '%@' value type: %@", key, String(describing: type(of: row.value(forKey: key))))
                        }
                    }
                    if let dictAt1 = row.dictionary(at: 1) {
                        NSLog("🔍 [DatabaseManager]   🧪 result.dictionary(at: 1) returned dict with keys: %@", dictAt1.keys.joined(separator: ", "))
                    } else {
                        NSLog("🔍 [DatabaseManager]   ⚠️ result.dictionary(at: 1) is nil!")
                    }
                }
                print("🧪 DIAGNOSTIC: Total rows returned: \(rowCount)")
            } catch {
                print("❌ DIAGNOSTIC: Vector query failed with error: \(error)")
            }
        }

        guard let db = database,
              let col = try? collection(named: AppConfig.documentsCollection),
              let query = try? db.createQuery("""
                  SELECT META().id
                  FROM `\(AppConfig.scopeName)`.`\(AppConfig.documentsCollection)`
                  """),
              let results = try? query.execute() else { return }

        var migrated = 0
        for result in results {
            guard let docId = result.string(at: 0),
                  let raw = try? col.document(id: docId) else { continue }
            let mutable = raw.toMutable()
            // boolean(forKey:) coerces numeric 1→true; setBoolean stores as proper CBL boolean
            mutable.setBoolean(raw.boolean(forKey: "isDeleted"),    forKey: "isDeleted")
            mutable.setBoolean(raw.boolean(forKey: "hasBlob"),      forKey: "hasBlob")
            mutable.setBoolean(raw.boolean(forKey: "ocrProcessed"), forKey: "ocrProcessed")
            
            // Clean up polluted tags if present (from old pipeline bugs)
            if let tagsArray = raw.array(forKey: "tags")?.toArray() as? [String] {
                let pollutedWords: Set<String> = ["visual", "labels:", "labels", "gray,", "visual,"]
                let cleanedTags = tagsArray.filter { !pollutedWords.contains($0.lowercased()) }
                if cleanedTags.count != tagsArray.count {
                    let mutableArray = MutableArrayObject()
                    for tag in cleanedTags {
                        mutableArray.addValue(tag)
                    }
                    mutable.setArray(mutableArray, forKey: "tags")
                    print("🔧 migrateDocumentBooleans: cleaned polluted tags for \(docId)")
                }
            }
            
            try? col.save(document: mutable)
            migrated += 1
        }

        if migrated > 0 {
            print("🔧 migrateDocumentBooleans: fixed \(migrated) documents")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
            }
        }
    }

    /// Writes default values for any fields added after initial release into stored documents
    /// that predate those fields. Safe to call on every launch — skips docs already migrated.
    func migrateDocumentSchema() {
        guard let db = database,
              let col = try? collection(named: AppConfig.documentsCollection),
              let query = try? db.createQuery("""
                  SELECT META().id
                  FROM `\(AppConfig.scopeName)`.`\(AppConfig.documentsCollection)`
                  WHERE searchBoost IS NOT VALUED OR feedbackTags IS NOT VALUED
                  """),
              let results = try? query.execute() else { return }

        var migrated = 0
        for result in results {
            guard let docId = result.string(at: 0),
                  let raw = try? col.document(id: docId) else { continue }
            let mutable = raw.toMutable()
            if raw.value(forKey: "searchBoost")  == nil { mutable.setFloat(0.0,    forKey: "searchBoost") }
            if raw.value(forKey: "feedbackTags") == nil { mutable.setArray(MutableArrayObject(), forKey: "feedbackTags") }
            try? col.save(document: mutable)
            migrated += 1
        }
        if migrated > 0 {
            print("🔧 migrateDocumentSchema: added missing fields to \(migrated) documents")
        }
    }

    // MARK: - Blob Attachment

    /// Attaches a file as a CBL blob so it persists in the database and syncs via App Services.
    func attachBlob(_ blob: Blob, toDocumentId docId: String) throws {
        let col = try collection(named: AppConfig.documentsCollection)
        guard let existing = try col.document(id: docId) else { throw VaultError.documentNotFound(docId) }
        let mutable = existing.toMutable()
        mutable.setBlob(blob, forKey: "fileBlob")
        mutable.setBoolean(true, forKey: "hasBlob")
        try col.save(document: mutable)
    }

    /// Returns (blobPresent, blobLength, localFileSize) for the document's storage diagnostics.
    func fetchBlobInfo(forDocumentId docId: String, localPath: String?) -> (blobPresent: Bool, blobLength: Int, localFileBytes: Int) {
        let col = try? collection(named: AppConfig.documentsCollection)
        let raw = try? col?.document(id: docId)
        let blob = raw?.blob(forKey: "fileBlob")
        let blobPresent = blob != nil
        let blobLength  = blob.map { Int($0.length) } ?? 0
        let localFileBytes: Int
        if let path = localPath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            localFileBytes = (attrs[.size] as? Int) ?? 0
        } else {
            localFileBytes = -1  // -1 = file not found
        }
        return (blobPresent, blobLength, localFileBytes)
    }

    /// Streams the blob for docId to a temp file, verifying SHA-256 integrity on the way.
    /// Returns a file URL the caller can pass to QuickLook. Caller owns cleanup.
    func extractBlobToURL(forDocumentId docId: String,
                          fileExtension ext: String,
                          expectedHash: String?) throws -> URL? {
        let col = try collection(named: AppConfig.documentsCollection)
        guard let raw  = try col.document(id: docId),
              let blob = raw.blob(forKey: "fileBlob") else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(docId + "." + ext)

        // Remove stale temp file from a prior extraction
        try? FileManager.default.removeItem(at: tempURL)

        if let stream = blob.contentStream {
            // Stream in 64 KB chunks — avoids loading large files fully into memory
            stream.open()
            defer { stream.close() }

            var hasher = SHA256()
            let bufSize = 65_536
            let buffer  = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buffer.deallocate() }

            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let fh = try FileHandle(forWritingTo: tempURL)
            defer { try? fh.close() }

            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: bufSize)
                guard n > 0 else { break }
                let chunk = Data(bytes: buffer, count: n)
                hasher.update(data: chunk)
                fh.write(chunk)
            }

            if let expected = expectedHash {
                let computed = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
                if computed != expected {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw VaultError.integrityCheckFailed
                }
            }
        } else if let data = blob.content {
            // Fallback: small blob loaded fully into memory
            if let expected = expectedHash {
                let computed = SHA256.hash(data: data)
                    .compactMap { String(format: "%02x", $0) }.joined()
                if computed != expected {
                    throw VaultError.integrityCheckFailed
                }
            }
            try data.write(to: tempURL, options: .atomic)
        } else {
            return nil
        }

        return tempURL
    }

    // MARK: - Tenant Reconfiguration

    func reconfigure(for tenantId: String, username: String) {
        appServicesSyncManager?.disableAppServices()
        appServicesSyncManager = nil
        syncCancellable = nil
        isAppServicesEnabled = false

        changeTokens.forEach { $0.remove() }
        changeTokens = []

        try? database?.close()
        database = nil

        AppConfig.currentTenantId = tenantId
        AppConfig.currentUsername  = username

        openDatabase()
        setupIndexes()
        setupChangeListeners()
        setupAppServicesIntegration()

        if AppConfig.enableAppServicesSync { enableAppServices() }
    }

    // MARK: - App Services

    private func setupAppServicesIntegration() {
        guard let db = database else { return }
        let manager = AppServicesSyncManager(database: db)
        appServicesSyncManager = manager
        // Forward sync state changes so any view observing DatabaseManager re-renders
        syncCancellable = manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func enableAppServices() {
        isAppServicesEnabled = true
        appServicesSyncManager?.enableAppServices()
    }

    func disableAppServices() {
        isAppServicesEnabled = false
        appServicesSyncManager?.disableAppServices()
    }

    func getAppServicesSyncState() -> AppServicesSyncState? {
        appServicesSyncManager?.syncState
    }

    // MARK: - Annotation CRUD

    func saveAnnotation(_ annotation: Annotation) throws {
        let col = try collection(named: AppConfig.annotationsCollection)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(annotation)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VaultError.encodingFailed
        }
        let mutable = MutableDocument(id: annotation.id, data: dict)
        mutable.setBoolean(annotation.resolved, forKey: "resolved")
        try col.save(document: mutable)
        
        // Notify change
        NotificationCenter.default.post(name: .vaultAnnotationsChanged, object: nil)
    }

    func fetchAnnotations(forDocumentId docId: String) throws -> [Annotation] {
        guard let db = database else { return [] }
        let scope = AppConfig.scopeName
        let coll  = AppConfig.annotationsCollection

        let sql = "SELECT META().id, * FROM `\(scope)`.`\(coll)` WHERE documentId = '\(docId)' ORDER BY createdAt ASC"
        let query = try db.createQuery(sql)
        let results = try query.execute()
        
        var annotations: [Annotation] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for row in results {
            guard let dict = row.dictionary(at: 1)?.toDictionary() else { continue }
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let annotation = try? decoder.decode(Annotation.self, from: data) {
                annotations.append(annotation)
            }
        }
        return annotations
    }

    // MARK: - Matter Recommendations (Vector similarity suggestion)
    
    struct MatterSuggestion: Identifiable {
        let id = UUID()
        let matter: String
        let client: String
        let score: Double
    }
    
    func getSuggestedMatters(forDocument doc: VaultDocument) -> [MatterSuggestion] {
        guard let docEmbedding = doc.embedding, !docEmbedding.isEmpty else { return [] }
        
        do {
            let allDocs = try fetchAllDocuments()
            var matterGroups: [String: [(doc: VaultDocument, similarity: Double)]] = [:]
            
            for otherDoc in allDocs where otherDoc.id != doc.id {
                guard let otherEmbedding = otherDoc.embedding, !otherEmbedding.isEmpty,
                      let matter = otherDoc.matter, !matter.isEmpty,
                      let client = otherDoc.client, !client.isEmpty else { continue }
                
                let sim = cosineSimilarity(docEmbedding, otherEmbedding)
                matterGroups[matter, default: []].append((otherDoc, sim))
            }
            
            var suggestions: [MatterSuggestion] = []
            
            for (matter, group) in matterGroups {
                let client = group.first?.doc.client ?? ""
                let maxSim = group.map { $0.similarity }.max() ?? 0.0
                let score = max(0.0, maxSim)
                if score > 0.1 {
                    suggestions.append(MatterSuggestion(matter: matter, client: client, score: score))
                }
            }
            
            return suggestions.sorted { $0.score > $1.score }
            
        } catch {
            print("⚠️ Error calculating matter suggestions: \(error)")
            return []
        }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        if normA == 0 || normB == 0 { return 0.0 }
        return Double(dotProduct / (sqrt(normA) * sqrt(normB)))
    }

    func writeLog(_ message: String) {
        let fm = FileManager.default
        guard let docsUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logUrl = docsUrl.appendingPathComponent("semantic_search_debug.txt")
        let formatted = "[\(Date())] \(message)\n"
        if let data = formatted.data(using: .utf8) {
            if fm.fileExists(atPath: logUrl.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logUrl) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logUrl)
            }
        }
    }
}

// MARK: - Vault Error

enum VaultError: LocalizedError {
    case databaseUnavailable
    case encodingFailed
    case documentNotFound(String)
    case duplicateDocument(name: String, hash: String)
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:          return "Database is not available"
        case .encodingFailed:               return "Failed to encode document"
        case .documentNotFound(let id):     return "Document not found: \(id)"
        case .duplicateDocument(let name, let hash):
            return "Duplicate detected — \"\(name)\" matches SHA-256: \(hash.prefix(16))…\nIdentical content cannot be uploaded twice."
        case .integrityCheckFailed:         return "File integrity check failed. The stored file may be corrupted."
        }
    }
}
