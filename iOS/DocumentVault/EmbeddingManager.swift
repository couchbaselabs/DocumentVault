@preconcurrency import Vision
import UIKit
import CoreImage
import NaturalLanguage

// MARK: - Embedding Manager
// Produces float-vector embeddings for both images and text.
// Image: Vision VNGenerateImageFeaturePrintRequest (existing, kept as-is)
// Text:  NLEmbedding sentence embedding (iOS 17+) — 512 dimensions

class EmbeddingManager: ObservableObject {
    static let shared = EmbeddingManager()
    private init() {}

    // MARK: - Warmup

    /// Proactively warms up the Natural Language Contextual Embedding model and requests model assets.
    func warmup() {
        #if targetEnvironment(simulator)
        // Simulator Bypass: Natural Language model compilation fails in sandbox on Simulator.
        // Word average model is pre-bundled and works instantly without download/compilation.
        print("💡 Simulator mode: using pre-bundled word average embedding to bypass sandbox restrictions")
        #else
        guard #available(iOS 17.0, *) else { return }
        guard let embedding = NLContextualEmbedding(language: .english) else { return }
        if !embedding.hasAvailableAssets {
            print("⏳ NLContextualEmbedding: requesting asset download...")
            embedding.requestAssets { result, error in
                switch result {
                case .available:
                    print("✅ NLContextualEmbedding: assets downloaded and ready")
                case .notAvailable:
                    print("⚠️ NLContextualEmbedding: assets not available on this device")
                case .error:
                    print("❌ NLContextualEmbedding: asset download failed: \(String(describing: error))")
                @unknown default:
                    break
                }
            }
        } else {
            print("✅ NLContextualEmbedding: assets already available on device")
        }
        #endif
    }

    // MARK: - Text Embeddings

    /// Generates a sentence embedding from text.
    /// Returns a 512-dimensional Float array, or nil on failure.
    func generateTextEmbedding(from text: String) async -> [Float]? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Fallback for older iOS versions
        guard #available(iOS 17.0, *) else {
            return generateTextEmbeddingLegacy(from: text)
        }

        #if targetEnvironment(simulator)
        // Simulator Sandbox Bypass:
        // On simulator, Apple's natural language daemon (naturallanguaged) fails to compile
        // contextual/sentence embedding models due to sandbox permission errors writing to the host Mac's
        // "/var/db/com.apple.naturallanguaged/". To prevent these crashes and logs, we bypass
        // Tier 1 & Tier 2 and go straight to the stable, pre-bundled word-level average embedding.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let vector = self.generateWordAverageEmbedding(from: text)
                continuation.resume(returning: vector)
            }
        }
        #else
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let input = String(text.prefix(2048))

                // Tier 1: Try Contextual Embedding (available on device/downloaded)
                if let embedding = NLContextualEmbedding(language: .english),
                   embedding.hasAvailableAssets {
                    do {
                        try embedding.load()
                        defer { embedding.unload() }
                        
                        if let result = try? embedding.embeddingResult(for: input, language: .english) {
                            let dim = embedding.dimension
                            var sum = [Double](repeating: 0.0, count: dim)
                            var count = 0
                            
                            let range = input.startIndex..<input.endIndex
                            result.enumerateTokenVectors(in: range) { (vector: [Double], tokenRange: Range<String.Index>) -> Bool in
                                for i in 0..<min(sum.count, vector.count) {
                                    sum[i] += vector[i]
                                }
                                count += 1
                                return true
                            }
                            
                            if count > 0 {
                                var floats = sum.map { Float($0 / Double(count)) }
                                // Ensure exactly 1024 dimensions (pad or truncate if different)
                                let targetDim = 1024
                                if floats.count < targetDim {
                                    floats += [Float](repeating: 0, count: targetDim - floats.count)
                                } else if floats.count > targetDim {
                                    floats = Array(floats.prefix(targetDim))
                                }
                                let normalized = Self.l2Normalize(floats)
                                print("✅ Text embedding (contextual token avg): \(normalized.count) dimensions, magnitude≈1")
                                continuation.resume(returning: normalized)
                                return
                            }
                        }
                    } catch {
                        print("⚠️ NLContextualEmbedding load failed: \(error)")
                    }
                }

                // Tier 2: Try NLEmbedding sentence model
                if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english),
                   let vector = sentenceEmbedding.vector(for: input) {
                    let floats = Self.l2Normalize(vector.map { Float($0) })
                    print("✅ Text embedding (sentence): \(floats.count) dimensions, magnitude≈1")
                    continuation.resume(returning: floats)
                    return
                }

                // Tier 3: Word-level average fallback (always available)
                print("⚠️ NLContextualEmbedding and sentence models unavailable — falling back to word embedding")
                let vector = self.generateWordAverageEmbedding(from: text)
                continuation.resume(returning: vector)
            }
        }
        #endif
    }

    /// Helper to generate word-level averaged and normalized 512-dim embedding.
    private func generateWordAverageEmbedding(from text: String) -> [Float]? {
        let input = String(text.prefix(2048))
        guard let wordEmbedding = NLEmbedding.wordEmbedding(for: .english) else {
            print("⚠️ NLEmbedding word model unavailable")
            return nil
        }

        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = input
        let dim = wordEmbedding.dimension
        var sum = [Double](repeating: 0, count: dim)
        var wordCount = 0
        tagger.enumerateTags(in: input.startIndex..<input.endIndex,
                             unit: .word, scheme: .tokenType) { _, range in
            let word = String(input[range]).lowercased()
            if let vec = wordEmbedding.vector(for: word) {
                for i in 0..<min(dim, vec.count) { sum[i] += vec[i] }
                wordCount += 1
            }
            return true
        }

        guard wordCount > 0 else { return nil }
        var raw = Self.l2Normalize(sum.map { Float($0 / Double(wordCount)) })

        // Pad or truncate to exactly 1024 dims to match the vector index
        let targetDim = 1024
        if raw.count < targetDim {
            raw += [Float](repeating: 0, count: targetDim - raw.count)
            raw = Self.l2Normalize(raw)  // re-normalize after padding
        } else if raw.count > targetDim {
            raw = Self.l2Normalize(Array(raw.prefix(targetDim)))
        }
        print("✅ Text embedding (word avg): \(raw.count) dimensions, magnitude≈1")
        return raw
    }

    /// Fallback for iOS < 17: uses word-level NLEmbedding and averages vectors.
    private func generateTextEmbeddingLegacy(from text: String) -> [Float]? {
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text

        guard let wordEmbedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        let dim = wordEmbedding.dimension

        var sum = [Double](repeating: 0, count: dim)
        var count = 0

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                              unit: .word, scheme: .tokenType) { _, range in
            let word = String(text[range]).lowercased()
            if let vec = wordEmbedding.vector(for: word) {
                for i in 0..<min(dim, vec.count) { sum[i] += vec[i] }
                count += 1
            }
            return true
        }

        guard count > 0 else { return nil }
        var raw = Self.l2Normalize(sum.map { Float($0 / Double(count)) })
        let targetDim = 1024
        if raw.count < targetDim {
            raw += [Float](repeating: 0, count: targetDim - raw.count)
            raw = Self.l2Normalize(raw)
        } else if raw.count > targetDim {
            raw = Self.l2Normalize(Array(raw.prefix(targetDim)))
        }
        return raw
    }

    // MARK: - Normalization

    static func l2Normalize(_ v: [Float]) -> [Float] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }

    // MARK: - Image Embeddings (unchanged from original)

    func generateEmbedding(from image: UIImage) async -> [Float]? {
        guard let cgImage = image.cgImage, isImageValid(cgImage) else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<[Float]?, Never>) in
            nonisolated(unsafe) let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    print("❌ Vision request failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let results = request.results as? [VNFeaturePrintObservation],
                      let featurePrint = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let embedding = Self.l2Normalize(self.convertFeaturePrint(featurePrint))
                Swift.print("✅ Image embedding: \(embedding.count) dimensions, magnitude≈1")
                continuation.resume(returning: embedding)
            }
            request.revision = VNGenerateImageFeaturePrintRequestRevision1

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }
    }

    private func convertFeaturePrint(_ fp: VNFeaturePrintObservation) -> [Float] {
        let count = fp.elementCount
        switch fp.elementType {
        case .float:
            return fp.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        case .double:
            let doubles = fp.data.withUnsafeBytes { Array($0.bindMemory(to: Double.self).prefix(count)) }
            return doubles.map { Float($0) }
        default:
            return []
        }
    }

    // MARK: - Image Validation (unchanged)

    private func isImageValid(_ cgImage: CGImage) -> Bool {
        guard cgImage.width >= 50, cgImage.height >= 50 else { return false }
        guard let ctx = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let data = ctx.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: cgImage.width * cgImage.height)
        let step = max(1, (cgImage.width * cgImage.height) / 10_000)
        var total = 0, dark = 0, bright = 0, sampled = 0
        for i in stride(from: 0, to: cgImage.width * cgImage.height, by: step) {
            let v = Int(pixels[i]); total += v
            if v < 30 { dark += 1 } else if v > 200 { bright += 1 }
            sampled += 1
        }
        guard sampled > 0 else { return false }
        let avg = total / sampled
        let darkRatio = Double(dark) / Double(sampled)
        let brightRatio = Double(bright) / Double(sampled)
        return avg >= 20 && darkRatio <= 0.9 && brightRatio <= 0.95
    }

    func preprocessImage(_ image: UIImage) -> UIImage {
        let target = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}
