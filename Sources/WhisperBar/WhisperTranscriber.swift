import Foundation
import WhisperKit

// MARK: - Transcription Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case noSpeechDetected
    case audioFileNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded yet. Please wait for initialisation to complete."
        case .noSpeechDetected:
            return "No speech detected in the recording."
        case .audioFileNotFound:
            return "Audio file not found."
        }
    }
}

// MARK: - Whisper Transcriber

/// Wraps WhisperKit to provide local, fully-offline speech-to-text.
/// The model is downloaded once (to ~/Library/Caches by WhisperKit) and
/// runs entirely on-device afterwards.
final class WhisperTranscriber {

    private var whisperKit: WhisperKit?

    // MARK: - Model loading

    /// Downloads (if needed) and loads the specified Whisper model into memory.
    /// `modelName` accepts short names like "tiny", "base", "small", "medium".
    /// Progress is reported on [0, 1]; the closure may be called from a background thread.
    func loadModel(
        _ modelName: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {

        onProgress?(0.05)

        // Use the direct named-parameter init which is stable across WhisperKit 0.9+
        // WhisperKit will download the model from HuggingFace on first use and cache it
        // in ~/Library/Caches — subsequent launches are fully offline.
        whisperKit = try await WhisperKit(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )

        onProgress?(1.0)
    }

    // MARK: - Transcription

    /// Transcribes the WAV file at `audioURL` and returns the cleaned text.
    /// Deletes the temp file after a successful transcription.
    func transcribe(audioURL: URL) async throws -> String {
        guard let pipe = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        let results = try await pipe.transcribe(audioPath: audioURL.path)

        // Clean up the temporary audio file
        try? FileManager.default.removeItem(at: audioURL)

        let text = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw TranscriptionError.noSpeechDetected
        }

        return text
    }

    // MARK: - Helpers

    var isLoaded: Bool { whisperKit != nil }
}
