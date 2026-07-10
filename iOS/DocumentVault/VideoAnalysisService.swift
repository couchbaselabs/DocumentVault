import Foundation
import AVFoundation
import Vision
import UIKit

// MARK: - Video Analysis Result

struct VideoAnalysis {
    var transcript: String       // speech-to-text from audio track
    var frameLabels: [String]    // Vision scene/object labels from sampled frames
    var duration: Double         // seconds
}

// MARK: - Video Analysis Service
// Samples frames from a video at regular intervals, runs Vision classification on each,
// and transcribes the audio track via SpeechTranscriptionService.

actor VideoAnalysisService {
    static let shared = VideoAnalysisService()
    private init() {}

    private let transcriber = SpeechTranscriptionService.shared

    func analyze(url: URL) async -> VideoAnalysis {
        let asset    = AVURLAsset(url: url)
        let duration = await assetDuration(asset)
        async let transcript = transcriber.transcribe(url: url)
        async let labels     = sampleFrameLabels(asset: asset, duration: duration)
        return VideoAnalysis(
            transcript:  await transcript,
            frameLabels: await labels,
            duration:    duration
        )
    }

    // MARK: - Private

    private func assetDuration(_ asset: AVURLAsset) async -> Double {
        let cmDuration = try? await asset.load(.duration)
        return cmDuration.map { CMTimeGetSeconds($0) } ?? 0
    }

    private func sampleFrameLabels(asset: AVURLAsset, duration: Double) async -> [String] {
        guard duration > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)

        // Sample up to 8 frames evenly spaced (or every 10 s, whichever is fewer)
        let interval   = max(duration / 8, 10)
        var timestamps: [CMTime] = []
        var t = 0.0
        while t < duration && timestamps.count < 8 {
            timestamps.append(CMTimeMakeWithSeconds(t, preferredTimescale: 600))
            t += interval
        }

        var allLabels: [String] = []
        for time in timestamps {
            guard let cg = await cgImage(from: generator, at: time) else { continue }
            let labels = await classifyFrame(cg)
            allLabels.append(contentsOf: labels)
        }

        // Deduplicate preserving order
        let seen = NSMutableOrderedSet(array: allLabels)
        return seen.array as? [String] ?? allLabels
    }

    private func cgImage(from generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
        await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                continuation.resume(returning: error == nil ? image : nil)
            }
        }
    }

    private func classifyFrame(_ cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            nonisolated(unsafe) let request = VNClassifyImageRequest { req, error in
                guard error == nil,
                      let results = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                var tags: [String] = []
                for obs in results where obs.confidence > 0.2 {
                    let levels = obs.identifier.split(separator: "_").map(String.init)
                    for level in levels {
                        if let clean = cleanVideoLabel(level) { tags.append(clean) }
                    }
                    if tags.count >= 10 { break }
                }
                continuation.resume(returning: tags)
            }
            nonisolated(unsafe) let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
        }
    }
}

private func cleanVideoLabel(_ raw: String) -> String? {
    let blocked: Set<String> = ["default", "abstract", "no", "yes", "other", "misc"]
    guard !blocked.contains(raw), raw.count > 2 else { return nil }
    return raw.replacingOccurrences(of: "-", with: " ")
}
