import Foundation
@preconcurrency import Vision
import PDFKit
import UIKit
import UniformTypeIdentifiers

// MARK: - Extracted Content

struct ExtractedContent {
    var text: String
    var pageCount: Int
    var language: String?
    var wordCount: Int { text.split(separator: " ").count }
}

// MARK: - Text Extraction Service

actor TextExtractionService {
    static let shared = TextExtractionService()
    private init() {}

    // MARK: - Main Entry Point

    func extract(from url: URL, mimeType: String) async -> ExtractedContent {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return extractPDF(url: url)
        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "gif":
            return await extractViaOCR(url: url)
        case "txt", "md", "rtf", "log":
            return extractPlainText(url: url)
        case "csv":
            return extractCSV(url: url)
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "caf":
            return await extractAudio(url: url)
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return await extractVideo(url: url)
        default:
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return ExtractedContent(text: text, pageCount: 1)
            }
            return await extractViaOCR(url: url)
        }
    }

    // MARK: - Audio via SFSpeechRecognizer

    private func extractAudio(url: URL) async -> ExtractedContent {
        let transcript = await SpeechTranscriptionService.shared.transcribe(url: url)
        return ExtractedContent(text: transcript, pageCount: 1, language: nil)
    }

    // MARK: - Video via AVFoundation + Vision + Speech

    private func extractVideo(url: URL) async -> ExtractedContent {
        let analysis = await VideoAnalysisService.shared.analyze(url: url)
        // Combine transcript + frame labels into a single text blob for FTS/embedding
        var parts: [String] = []
        if !analysis.transcript.isEmpty { parts.append(analysis.transcript) }
        if !analysis.frameLabels.isEmpty {
            parts.append("Visual content: " + analysis.frameLabels.joined(separator: ", "))
        }
        return ExtractedContent(
            text: parts.joined(separator: "\n\n"),
            pageCount: 1,
            language: nil
        )
    }

    func extract(from data: Data, fileExtension ext: String) async -> ExtractedContent {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try? data.write(to: tmpURL)
        let result = await extract(from: tmpURL, mimeType: "")
        try? FileManager.default.removeItem(at: tmpURL)
        return result
    }

    // MARK: - PDF via PDFKit

    private func extractPDF(url: URL) -> ExtractedContent {
        guard let doc = PDFDocument(url: url) else {
            return ExtractedContent(text: "", pageCount: 0)
        }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let text = page.string {
                pages.append(text)
            }
        }
        let combined = pages.joined(separator: "\n\n")
        return ExtractedContent(text: combined, pageCount: doc.pageCount)
    }

    // MARK: - OCR via Vision

    private func extractViaOCR(url: URL) async -> ExtractedContent {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            return ExtractedContent(text: "", pageCount: 1)
        }

        return await withCheckedContinuation { continuation in
            nonisolated(unsafe) let request = VNRecognizeTextRequest { req, error in
                guard error == nil,
                      let results = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ExtractedContent(text: "", pageCount: 1))
                    return
                }
                let lines = results.compactMap { $0.topCandidates(1).first?.string }
                let text  = lines.joined(separator: "\n")
                continuation.resume(returning: ExtractedContent(text: text, pageCount: 1))
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true

            nonisolated(unsafe) let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    // MARK: - Plain Text

    private func extractPlainText(url: URL) -> ExtractedContent {
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1252]
        for enc in encodings {
            if let text = try? String(contentsOf: url, encoding: enc) {
                return ExtractedContent(text: text, pageCount: 1)
            }
        }
        return ExtractedContent(text: "", pageCount: 1)
    }

    // MARK: - CSV

    private func extractCSV(url: URL) -> ExtractedContent {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ExtractedContent(text: "", pageCount: 1)
        }
        // Convert CSV rows to readable text for FTS indexing
        let rows = text.components(separatedBy: "\n")
        let readable = rows.map { $0.replacingOccurrences(of: ",", with: " ") }.joined(separator: "\n")
        return ExtractedContent(text: readable, pageCount: 1)
    }
}
