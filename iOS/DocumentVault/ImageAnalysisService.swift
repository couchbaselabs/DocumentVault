@preconcurrency import Vision
import CoreImage
import UIKit

// MARK: - Image Analysis Result

struct ImageAnalysis {
    var labels: [String]       // Vision scene/object classification tags
    var dominantColor: String? // color name: "blue", "green", etc.
}

// MARK: - Image Analysis Service

actor ImageAnalysisService {
    static let shared = ImageAnalysisService()
    private init() {}

    nonisolated private func logDebug(_ message: String) {
        let logPath = "/Users/austin.gonyou/Downloads/Apps/CBDemoChallengeApp/vision_debug.log"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        let line = "[\(timeStr)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    func analyze(url: URL, originalName: String? = nil) async -> ImageAnalysis {
        let displayName = originalName ?? url.lastPathComponent
        logDebug("analyze starting for \(displayName)")
        guard let image = UIImage(contentsOfFile: url.path) else {
            logDebug("analyze error: Failed to load UIImage from \(url.path)")
            return ImageAnalysis(labels: [], dominantColor: nil)
        }
        guard let cg = image.cgImage else {
            logDebug("analyze error: image.cgImage is nil for \(url.path)")
            return ImageAnalysis(labels: [], dominantColor: nil)
        }
        
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        logDebug("analyze: image size: \(image.size), orientation: \(image.imageOrientation.rawValue) -> \(orientation.rawValue)")
        
        var labels = await classifyImage(cg, orientation: orientation)
        logDebug("analyze: classifyImage returned labels: \(labels)")
        
        // If classification fails or returns no tags (e.g. simulator without Vision ML assets),
        // fallback to VNDetectFaceRectanglesRequest which is bundled and works in simulator.
        if labels.isEmpty {
            logDebug("analyze: labels empty, triggering face detection fallback")
            labels = await detectFaces(cg, orientation: orientation)
            logDebug("analyze: face detection fallback returned labels: \(labels)")
            
            // If still empty (common in simulator with standard scenes), extract keywords from the filename to help index the document semantically.
            if labels.isEmpty {
                let filenameKeywords = extractKeywords(from: displayName)
                if !filenameKeywords.isEmpty {
                    labels = filenameKeywords
                    logDebug("analyze: parsed keywords from filename: \(labels)")
                }
            }
        }
        
        let color = dominantColor(cg)
        logDebug("analyze: dominantColor returned: \(color ?? "nil")")
        return ImageAnalysis(labels: labels, dominantColor: color)
    }

    private func extractKeywords(from filename: String) -> [String] {
        let nameWithoutExtension = (filename as NSString).deletingPathExtension
        let cleaned = nameWithoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let components = cleaned.components(separatedBy: .whitespacesAndNewlines)
        let stopwords: Set<String> = ["image", "photo", "pic", "scan", "screen", "shot", "screenshot", "a", "the", "in", "on", "at", "of", "and", "or", "for", "with", "doc"]
        return components
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    // MARK: - Vision Classification

    private func classifyImage(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        await withCheckedContinuation { rawContinuation in
            let safeContinuation = SafeContinuation(rawContinuation)
            nonisolated(unsafe) let request = VNClassifyImageRequest { req, error in
                if let error = error {
                    self.logDebug("classifyImage callback error: \(error.localizedDescription)")
                    safeContinuation.resume(returning: [])
                    return
                }
                guard let results = req.results as? [VNClassificationObservation] else {
                    self.logDebug("classifyImage callback: no results found or cast failed")
                    safeContinuation.resume(returning: [])
                    return
                }
                var tags: [String] = []
                for obs in results where obs.confidence > 0.2 {
                    let levels = obs.identifier.split(separator: "_").map(String.init)
                    for level in levels {
                        if let clean = cleanLabel(level) { tags.append(clean) }
                    }
                    if tags.count >= 15 { break }
                }
                let deduped = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
                self.logDebug("classifyImage callback success: found \(results.count) results, deduped to: \(deduped)")
                safeContinuation.resume(returning: deduped)
            }
            nonisolated(unsafe) let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    self.logDebug("classifyImage perform threw error: \(error.localizedDescription)")
                    safeContinuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Face Detection Fallback

    private func detectFaces(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        await withCheckedContinuation { rawContinuation in
            let safeContinuation = SafeContinuation(rawContinuation)
            nonisolated(unsafe) let request = VNDetectFaceRectanglesRequest { req, error in
                if let error = error {
                    self.logDebug("detectFaces callback error: \(error.localizedDescription)")
                    safeContinuation.resume(returning: [])
                    return
                }
                guard let results = req.results as? [VNFaceObservation] else {
                    self.logDebug("detectFaces callback: results nil or cast failed")
                    safeContinuation.resume(returning: [])
                    return
                }
                self.logDebug("detectFaces callback success: found \(results.count) faces")
                if results.isEmpty {
                    safeContinuation.resume(returning: [])
                } else {
                    safeContinuation.resume(returning: ["people", "person", "face"])
                }
            }
            nonisolated(unsafe) let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    self.logDebug("detectFaces perform threw error: \(error.localizedDescription)")
                    safeContinuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Dominant Color via CIAreaAverage

    private func dominantColor(_ cgImage: CGImage) -> String? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ciImage,
                                                 kCIInputExtentKey: CIVector(cgRect: ciImage.extent)]),
              let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext()
        ctx.render(output,
                   toBitmap: &pixel,
                   rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8,
                   colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = Double(pixel[0]) / 255
        let g = Double(pixel[1]) / 255
        let b = Double(pixel[2]) / 255
        return colorName(r: r, g: g, b: b)
    }

    // MARK: - Color Naming

    private func colorName(r: Double, g: Double, b: Double) -> String {
        let brightness  = (r + g + b) / 3.0
        if brightness < 0.15 { return "black" }
        if brightness > 0.85 { return "white" }

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let saturation = maxC - minC
        if saturation < 0.15 { return "gray" }

        var hue: Double = 0
        if maxC == r      { hue = (g - b) / saturation }
        else if maxC == g { hue = 2 + (b - r) / saturation }
        else              { hue = 4 + (r - g) / saturation }
        hue *= 60
        if hue < 0 { hue += 360 }

        switch hue {
        case 0..<20:    return "red"
        case 20..<45:   return "orange"
        case 45..<70:   return "yellow"
        case 70..<160:  return "green"
        case 160..<200: return "teal"
        case 200..<260: return "blue"
        case 260..<290: return "purple"
        case 290..<330: return "pink"
        default:        return "red"
        }
    }
}

private func cleanLabel(_ identifier: String) -> String? {
    // VNClassifyImageRequest returns identifiers like "outdoor_natural", "animal_mammal_dog"
    // Skip low-signal catch-alls
    let blocked: Set<String> = ["default", "abstract", "no", "yes", "other", "misc"]
    let parts = identifier.split(separator: "_").map(String.init)
    // Use the last (most specific) segment
    guard let label = parts.last, !blocked.contains(label) else { return nil }
    return label.replacingOccurrences(of: "-", with: " ")
}

// MARK: - Orientation Mapping

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Safe Checked Continuation

private final class SafeContinuation<T>: Sendable {
    private let continuation: CheckedContinuation<T, Never>
    private let lock = NSLock()
    nonisolated(unsafe) private var didResume = false

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
