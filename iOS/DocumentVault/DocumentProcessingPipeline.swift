import Foundation
import UIKit
import CouchbaseLiteSwift

// MARK: - Ingest Result

enum IngestResult {
    case created(VaultDocument)
    case restored(VaultDocument, deletedAt: Date?)
    case blobAttached(VaultDocument)   // existing metadata-only record now has its content
}

// MARK: - Document Processing Pipeline
// Orchestrates: ingest → extract text → generate embedding → save back to CBL
// All steps are local and offline-capable. processingStatus is persisted per step.

actor DocumentProcessingPipeline {
    static let shared = DocumentProcessingPipeline()
    private init() {}

    private let storage   = ContentStorageService.shared
    private let extractor = TextExtractionService.shared
    private let embedder  = EmbeddingService.shared
    private let analyzer  = ImageAnalysisService.shared

    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "gif"]

    // MARK: - Ingest from file URL (file picker / share extension)

    func ingest(
        fileURL: URL,
        ownerId: String,
        tenantId: String,
        folderId: String? = nil,
        tags: [String] = [],
        db: DatabaseManager
    ) async throws -> IngestResult {
        let ext      = fileURL.pathExtension.lowercased()
        let mimeType = mimeType(for: ext)
        let fileName = fileURL.lastPathComponent

        // 1. Copy file into vault sandbox
        let tempId    = "tmp_\(UUID().uuidString)"
        let localPath = try await storage.copy(from: fileURL, for: tempId)
        // Read from the LOCAL COPY — the original fileURL's security scope may expire
        // before this async function runs, making a direct read of fileURL fail.
        let fileData  = (try? Data(contentsOf: URL(fileURLWithPath: localPath))) ?? Data()
        let hash      = await storage.sha256(data: fileData)
        let size      = await storage.fileSize(at: localPath)

        // 2. Duplicate / restore check
        if let existing = try? db.findDocument(byHash: hash) {
            if existing.hasBlob {
                // Content already stored — true duplicate, reject
                await storage.delete(for: tempId)
                throw VaultError.duplicateDocument(name: existing.name, hash: hash)
            }
            // Metadata-only record: attach the uploaded content and re-run processing
            return try await attachContentToExisting(
                existing, tempId: tempId, localPath: localPath,
                mimeType: mimeType, ownerId: ownerId, db: db
            )
        }
        if let deleted = try? db.findDeletedDocument(byHash: hash) {
            let deletedAt = deleted.deletedAt
            try db.restoreDocument(id: deleted.id, actor: ownerId)
            if !deleted.hasBlob {
                // Deleted AND metadata-only: attach content while restoring
                return try await attachContentToExisting(
                    (try? db.fetchDocument(id: deleted.id)) ?? deleted,
                    tempId: tempId, localPath: localPath,
                    mimeType: mimeType, ownerId: ownerId, db: db
                )
            }
            await storage.delete(for: tempId)
            let restored = (try? db.fetchDocument(id: deleted.id)) ?? deleted
            return .restored(restored, deletedAt: deletedAt)
        }

        // 3. Create initial document record
        var doc = VaultDocument(
            name: fileName,
            fileExtension: ext,
            mimeType: mimeType,
            size: size,
            folderId: folderId,
            ownerId: ownerId,
            tenantId: tenantId,
            tags: tags,
            source: DocumentSource(type: .filePicker, capturedBy: ownerId, capturedAt: Date())
        )
        doc.contentHash      = hash
        doc.contentLocalPath = localPath

        // Append ingestion custody event
        let uploadDeviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        doc.custodyChain.append(CustodyEvent(
            actor: ownerId,
            action: .uploaded,
            deviceId: uploadDeviceId
        ))

        // Move file to stable path using the final doc ID
        let stablePath = try await storage.copy(from: URL(fileURLWithPath: localPath), for: doc.id)
        doc.contentLocalPath = stablePath
        await storage.delete(for: tempId)   // cleanup temp (uses correct ID now)

        // 3. Save with pending status
        doc.processingStatus = .extracting
        try db.saveDocument(doc)

        // 4. Attach file as CBL blob — persists in DB and syncs via App Services
        let blobURL = URL(fileURLWithPath: stablePath)
        do {
            let blob = try Blob(contentType: mimeType, fileURL: blobURL)
            try db.attachBlob(blob, toDocumentId: doc.id)
        } catch {
            print("⚠️ Blob attachment failed for \(doc.id): \(error). Document stored as metadata-only.")
        }

        // 5. Extract text (async, updates doc in place)
        Task { await processExtraction(for: doc.id, db: db) }

        return .created(doc)
    }

    // MARK: - Ingest from camera capture

    func ingest(
        image: UIImage,
        ownerId: String,
        tenantId: String,
        folderId: String? = nil,
        tags: [String] = [],
        db: DatabaseManager
    ) async throws -> IngestResult {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw VaultError.encodingFailed
        }

        let docId    = "Doc_\(UUID().uuidString)"
        let localPath = try await storage.save(data: data, for: docId, extension: "jpg")
        let hash      = await storage.sha256(data: data)
        let thumb     = await storage.generateThumbnail(from: image)

        // Duplicate / restore check
        if let existing = try? db.findDocument(byHash: hash) {
            if existing.hasBlob {
                await storage.delete(for: docId)
                throw VaultError.duplicateDocument(name: existing.name, hash: hash)
            }
            // Metadata-only: attach camera data directly (no file URL needed)
            await storage.delete(for: docId)
            return try await attachDataToExisting(
                existing, data: data, mimeType: "image/jpeg", ownerId: ownerId, db: db
            )
        }
        if let deleted = try? db.findDeletedDocument(byHash: hash) {
            let deletedAt = deleted.deletedAt
            try db.restoreDocument(id: deleted.id, actor: ownerId)
            if !deleted.hasBlob {
                await storage.delete(for: docId)
                return try await attachDataToExisting(
                    (try? db.fetchDocument(id: deleted.id)) ?? deleted,
                    data: data, mimeType: "image/jpeg", ownerId: ownerId, db: db
                )
            }
            await storage.delete(for: docId)
            let restored = (try? db.fetchDocument(id: deleted.id)) ?? deleted
            return .restored(restored, deletedAt: deletedAt)
        }

        var doc = VaultDocument(
            id: docId,
            name: "Scan_\(dateStamp()).jpg",
            fileExtension: "jpg",
            mimeType: "image/jpeg",
            size: data.count,
            folderId: folderId,
            ownerId: ownerId,
            tenantId: tenantId,
            tags: tags,
            source: DocumentSource(type: .camera, capturedBy: ownerId, capturedAt: Date())
        )
        doc.contentHash      = hash
        doc.contentLocalPath = localPath
        let scanDeviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        if thumb != nil {
            doc.custodyChain.append(CustodyEvent(actor: ownerId, action: .scanned, deviceId: scanDeviceId))
        }

        doc.processingStatus = .extracting
        try db.saveDocument(doc)

        // Attach JPEG as CBL blob
        do {
            let blob = Blob(contentType: "image/jpeg", data: data)
            try db.attachBlob(blob, toDocumentId: doc.id)
        } catch {
            print("⚠️ Blob attachment failed for \(doc.id): \(error). Document stored as metadata-only.")
        }

        Task { await processExtraction(for: doc.id, db: db) }
        return .created(doc)
    }

    // MARK: - Blob Repair Helpers

    /// Attaches a file-backed blob to a metadata-only record, re-triggers processing.
    private func attachContentToExisting(
        _ existing: VaultDocument,
        tempId: String,
        localPath: String,
        mimeType: String,
        ownerId: String,
        db: DatabaseManager
    ) async throws -> IngestResult {
        let stablePath = try await storage.copy(from: URL(fileURLWithPath: localPath), for: existing.id)
        await storage.delete(for: tempId)

        do {
            let blob = try Blob(contentType: mimeType, fileURL: URL(fileURLWithPath: stablePath))
            try db.attachBlob(blob, toDocumentId: existing.id)
        } catch {
            print("⚠️ Blob attachment failed for \(existing.id): \(error)")
        }

        var updated = existing
        updated.contentLocalPath = stablePath
        updated.processingStatus = .extracting
        updated.updatedAt        = Date()
        updated.custodyChain.append(CustodyEvent(
            actor: ownerId, action: .contentReplaced,
            notes: "Content attached from re-upload (was metadata-only)"
        ))
        try db.saveDocument(updated)
        let fresh = (try? db.fetchDocument(id: existing.id)) ?? updated
        Task { await processExtraction(for: fresh.id, db: db) }
        return .blobAttached(fresh)
    }

    /// Attaches in-memory data as a blob to a metadata-only record, re-triggers processing.
    private func attachDataToExisting(
        _ existing: VaultDocument,
        data: Data,
        mimeType: String,
        ownerId: String,
        db: DatabaseManager
    ) async throws -> IngestResult {
        let stablePath = try await storage.save(data: data, for: existing.id, extension: existing.fileExtension)

        do {
            let blob = Blob(contentType: mimeType, data: data)
            try db.attachBlob(blob, toDocumentId: existing.id)
        } catch {
            print("⚠️ Blob attachment failed for \(existing.id): \(error)")
        }

        var updated = existing
        updated.contentLocalPath = stablePath
        updated.processingStatus = .extracting
        updated.updatedAt        = Date()
        updated.custodyChain.append(CustodyEvent(
            actor: ownerId, action: .contentReplaced,
            notes: "Content attached from re-upload (was metadata-only)"
        ))
        try db.saveDocument(updated)
        let fresh = (try? db.fetchDocument(id: existing.id)) ?? updated
        Task { await processExtraction(for: fresh.id, db: db) }
        return .blobAttached(fresh)
    }

    // MARK: - Processing Steps

    private let summaryService = DocumentSummaryService.shared

    private let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "caf"]
    private let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

    private func processExtraction(for docId: String, db: DatabaseManager) async {
        guard var doc = try? db.fetchDocument(id: docId) else { return }

        guard let localPath = await ContentStorageService.shared.ensureLocalFileExists(
            forDocumentId: doc.id,
            fileExtension: doc.fileExtension,
            db: db
        ) else {
            print("⚠️ processExtraction: Could not resolve or extract local file for \(docId)")
            return
        }

        if doc.contentLocalPath != localPath {
            doc.contentLocalPath = localPath
            try? db.saveDocument(doc)
        }

        let fileURL = URL(fileURLWithPath: localPath)
        let ext     = doc.fileExtension.lowercased()
        let content = await extractor.extract(from: fileURL, mimeType: doc.mimeType)

        // Store full raw text for FTS
        doc.textContent  = content.text.isEmpty ? nil : content.text
        doc.ocrProcessed = true

        // Vision classification for images
        if imageExtensions.contains(ext) {
            let analysis = await analyzer.analyze(url: fileURL, originalName: doc.name)
            if !analysis.labels.isEmpty {
                doc.tags = Array(Set(doc.tags + analysis.labels))
                print("🏷️ Image tags for \(docId): \(doc.tags.joined(separator: ", "))")
            }
            if let color = analysis.dominantColor, !doc.tags.contains(color) {
                doc.tags.append(color)
            }
        }

        // AI summary — runs for any document with extractable text
        // (images use combined OCR text + visual tag surrogate; audio/video use transcript)
        var textForSummary: String
        if imageExtensions.contains(ext) {
            var parts: [String] = []
            if let ocrText = doc.textContent, !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(ocrText)
            }
            if !doc.tags.isEmpty {
                parts.append("Visual labels: \(doc.tags.joined(separator: ", "))")
            }
            textForSummary = parts.joined(separator: "\n")
        } else {
            textForSummary = content.text
        }

        // Append unresolved annotations (e.g. synced emails or third-party notes) to the summary source
        if let annotations = try? db.fetchAnnotations(forDocumentId: docId) {
            let activeNotes = annotations
                .filter { !$0.resolved }
                .map { $0.body }
                .joined(separator: "\n")
            if !activeNotes.isEmpty {
                textForSummary += "\n\n[Recent Case Matter Updates & Notes]:\n\(activeNotes)"
            }
        }

        if !textForSummary.isEmpty {
            let analysis = await summaryService.analyze(
                text: textForSummary,
                name: doc.name,
                mimeType: doc.mimeType
            )
            if !analysis.summary.isEmpty {
                doc.summary = analysis.summary
                print("📝 Summary for \(docId): \(analysis.summary.prefix(80))…")
            }
            if !analysis.topics.isEmpty {
                doc.tags = Array(Set(doc.tags + analysis.topics))
            }
            if !analysis.category.isEmpty && analysis.category != "other" {
                doc.contentCategory = analysis.category
                if !doc.tags.contains(analysis.category) {
                    doc.tags.append(analysis.category)
                }
            }
            if let author = analysis.author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.author = author
            }
            if let docType = analysis.docType, !docType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.profileDocType = docType
                doc.docType = docType
            }
        }

        doc.processingStatus = .embedding
        try? db.saveDocument(doc)

        // Embed the summary if available (richer semantic target than raw text);
        // fall back to raw text, then tag surrogate for images.
        // Filename is always prepended so name-based queries work semantically.
        let namePrefix = doc.name.replacingOccurrences(of: ".", with: " ")
        let bodyText = doc.summary
            ?? (content.text.isEmpty ? nil : content.text)
            ?? (doc.tags.isEmpty ? nil : doc.tags.joined(separator: " "))
        var embeddingText = bodyText.map { "\(namePrefix) \($0)" } ?? namePrefix

        // Influence embedding with active (unresolved) annotations so case matter updates steer vector search
        if let annotations = try? db.fetchAnnotations(forDocumentId: docId) {
            let activeNotes = annotations
                .filter { !$0.resolved }
                .map { $0.body }
                .joined(separator: " ")
            if !activeNotes.isEmpty {
                embeddingText += " \(activeNotes)"
                print("📝 Added \(annotations.filter { !$0.resolved }.count) active annotations to embedding text target for \(docId)")
            }
        }

        if !embeddingText.trimmingCharacters(in: .whitespaces).isEmpty {
            let surrogate = ExtractedContent(text: embeddingText, pageCount: content.pageCount)
            await processEmbedding(for: docId, content: surrogate, db: db)
        } else {
            doc.processingStatus = .complete
            try? db.saveDocument(doc)
        }
    }

    private func processEmbedding(for docId: String, content: ExtractedContent, db: DatabaseManager) async {
        guard var doc = try? db.fetchDocument(id: docId) else { return }

        let vector = await embedder.embed(
            extractedContent: content,
            documentExtension: doc.fileExtension
        )

        doc.embedding        = vector
        doc.processingStatus = .complete
        try? db.saveDocument(doc)

        print("✅ Pipeline complete for \(docId): \(vector?.count ?? 0)-dim embedding")
    }

    // MARK: - Retry

    func retryProcessing(for docId: String, db: DatabaseManager) async {
        guard var doc = try? db.fetchDocument(id: docId) else { return }

        // If blob is missing but local file exists, re-attach before processing
        if !doc.hasBlob, let localPath = doc.contentLocalPath,
           FileManager.default.fileExists(atPath: localPath) {
            do {
                let blob = try Blob(contentType: doc.mimeType, fileURL: URL(fileURLWithPath: localPath))
                try db.attachBlob(blob, toDocumentId: docId)
                print("🔧 Reprocess: re-attached blob for \(docId) from local file")
            } catch {
                print("⚠️ Reprocess: blob re-attach failed for \(docId): \(error)")
            }
        }

        doc.processingStatus = .extracting
        try? db.saveDocument(doc)
        await processExtraction(for: docId, db: db)
    }

    // MARK: - Helpers

    private func mimeType(for ext: String) -> String {
        let map: [String: String] = [
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "csv": "text/csv",
            "txt": "text/plain",
            "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "png": "image/png",
            "heic": "image/heic",
            "tiff": "image/tiff"
        ]
        return map[ext] ?? "application/octet-stream"
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
