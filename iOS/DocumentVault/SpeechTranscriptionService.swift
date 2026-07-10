import Foundation
import Speech
import AVFoundation

// MARK: - Speech Transcription Service
// Transcribes audio files and video audio tracks on-device via SFSpeechRecognizer.
// Requires NSSpeechRecognitionUsageDescription in Info.plist.

actor SpeechTranscriptionService {
    static let shared = SpeechTranscriptionService()
    private init() {}

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Transcribe

    /// Returns the transcribed text from any audio or video file URL.
    /// Uses on-device recognition; falls back to empty string if unavailable.
    func transcribe(url: URL) async -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            let granted = await SpeechTranscriptionService.requestAuthorization()
            guard granted else { return "" }
            return await transcribe(url: url)
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            return ""
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults  = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation             = true

        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
