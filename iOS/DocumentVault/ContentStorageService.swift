import Foundation
import UIKit
import CryptoKit

// MARK: - Content Storage Service
// Manages the on-device sandbox storage for document blobs.

actor ContentStorageService {
    static let shared = ContentStorageService()

    private let root: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("VaultContent", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Save

    /// Saves file data for a document, returns the local path string.
    func save(data: Data, for documentId: String, extension ext: String) throws -> String {
        let dir = root.appendingPathComponent(documentId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("content.\(ext)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    /// Copies an existing file URL into the vault sandbox.
    func copy(from sourceURL: URL, for documentId: String) throws -> String {
        let ext = sourceURL.pathExtension
        let dir = root.appendingPathComponent(documentId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = dir.appendingPathComponent("content.\(ext)")
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return destURL.path
    }

    // MARK: - Read

    func data(for documentId: String, extension ext: String) -> Data? {
        let fileURL = root.appendingPathComponent(documentId).appendingPathComponent("content.\(ext)")
        return try? Data(contentsOf: fileURL)
    }

    func fileURL(for localPath: String) -> URL? {
        let url = URL(fileURLWithPath: localPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Thumbnail

    /// Generates a small JPEG thumbnail for list view display.
    func generateThumbnail(from image: UIImage, maxDimension: CGFloat = 128) -> Data? {
        let size: CGSize
        let ratio = image.size.width / image.size.height
        if ratio > 1 {
            size = CGSize(width: maxDimension, height: maxDimension / ratio)
        } else {
            size = CGSize(width: maxDimension * ratio, height: maxDimension)
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return thumb.jpegData(compressionQuality: 0.6)
    }

    // MARK: - Hashing

    func sha256(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Delete

    func delete(for documentId: String) {
        let dir = root.appendingPathComponent(documentId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Size

    func fileSize(at path: String) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int) ?? 0
    }

    // MARK: - Dynamic Path Resolution & Self Healing

    nonisolated func resolveActualPath(forDocumentId docId: String, fileExtension ext: String) -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let rootDir = docs.appendingPathComponent("VaultContent", isDirectory: true)
        return rootDir.appendingPathComponent(docId).appendingPathComponent("content.\(ext)").path
    }

    func ensureLocalFileExists(
        forDocumentId docId: String,
        fileExtension ext: String,
        db: DatabaseManager
    ) async -> String? {
        let stablePath = resolveActualPath(forDocumentId: docId, fileExtension: ext)
        
        // If file already exists and is non-empty, we are good!
        if FileManager.default.fileExists(atPath: stablePath),
           let attrs = try? FileManager.default.attributesOfItem(atPath: stablePath),
           (attrs[.size] as? Int ?? 0) > 0 {
            return stablePath
        }
        
        // Otherwise, extract it from Couchbase Lite's blob store to restore/self-heal it!
        do {
            let fileURL = URL(fileURLWithPath: stablePath)
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            
            let col = try db.collection(named: AppConfig.documentsCollection)
            guard let raw = try col.document(id: docId),
                  let blob = raw.blob(forKey: "fileBlob"),
                  let stream = blob.contentStream else {
                return nil
            }
            
            stream.open()
            defer { stream.close() }
            
            FileManager.default.createFile(atPath: stablePath, contents: nil)
            let fh = try FileHandle(forWritingTo: fileURL)
            defer { try? fh.close() }
            
            let bufSize = 65_536
            let buffer  = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buffer.deallocate() }
            
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: bufSize)
                guard n > 0 else { break }
                let chunk = Data(bytes: buffer, count: n)
                fh.write(chunk)
            }
            
            print("🔧 Self-healed sandbox file: extracted blob for \(docId) to stable path")
            return stablePath
        } catch {
            print("⚠️ Failed to self-heal sandbox file for \(docId): \(error)")
            return nil
        }
    }
}
