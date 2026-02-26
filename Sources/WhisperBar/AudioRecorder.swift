import AVFoundation

// MARK: - Audio Recorder

/// Handles microphone recording and writes a 16 kHz mono WAV file that
/// WhisperKit can consume directly.
///
/// While recording, a 20 Hz timer samples the microphone amplitude and calls
/// `onLevel` with a normalised value in [0, 1] so the waveform UI can update.
final class AudioRecorder {

    /// Called on the **main thread** every ~50 ms with a normalised level [0, 1].
    var onLevel: ((Float) -> Void)?

    private var audioRecorder:    AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var levelTimer:       Timer?

    // MARK: - Permission

    /// Requests microphone access. Completion is dispatched to the main thread.
    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { completion(false) }
        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    // MARK: - Recording

    /// Starts recording to a temporary WAV file.
    /// Returns the URL that will hold the audio when recording is stopped.
    @discardableResult
    func startRecording() throws -> URL {
        // 16 kHz mono PCM-16 — optimal for Whisper
        let settings: [String: Any] = [
            AVFormatIDKey:             Int(kAudioFormatLinearPCM),
            AVSampleRateKey:           16_000.0,
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey:     false,
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperbar_\(Int(Date().timeIntervalSince1970)).wav")

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true   // required for level monitoring
        recorder.record()

        self.audioRecorder      = recorder
        self.currentRecordingURL = url

        startLevelMonitoring()
        return url
    }

    /// Stops the current recording and returns the URL of the recorded file.
    /// Returns `nil` if no recording was in progress.
    func stopRecording() -> URL? {
        stopLevelMonitoring()
        guard let recorder = audioRecorder else { return nil }
        recorder.stop()
        let url             = currentRecordingURL
        audioRecorder       = nil
        currentRecordingURL = nil
        return url
    }

    // MARK: - Level monitoring

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let db         = recorder.averagePower(forChannel: 0)   // −160 … 0 dB
            let normalised = max(0, min(1, (Float(db) + 50) / 50))  // map −50…0 → 0…1
            DispatchQueue.main.async { self.onLevel?(normalised) }
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - Cleanup

    /// Stops any active recording and deletes the temporary file.
    func cleanup() {
        stopLevelMonitoring()
        audioRecorder?.stop()
        audioRecorder = nil
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
        }
    }
}
