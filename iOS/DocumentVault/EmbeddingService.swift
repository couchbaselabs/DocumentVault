import Foundation

// MARK: - Embedding Service
// Thin wrapper around EmbeddingManager that handles text vs image routing
// and provides a queue for background embedding generation.

actor EmbeddingService {
    static let shared = EmbeddingService()
    private init() {}

    private let manager = EmbeddingManager.shared

    // MARK: - Text

    func embed(text: String) async -> [Float]? {
        await manager.generateTextEmbedding(from: text)
    }

    // MARK: - Image

    func embed(image: UIImage) async -> [Float]? {
        let preprocessed = manager.preprocessImage(image)
        return await manager.generateEmbedding(from: preprocessed)
    }

    // MARK: - Document (picks correct path)

    func embed(extractedContent: ExtractedContent, documentExtension ext: String) async -> [Float]? {
        guard !extractedContent.text.isEmpty else { return nil }
        return await embed(text: extractedContent.text)
    }
}

// UIImage import needed for embed(image:)
import UIKit
