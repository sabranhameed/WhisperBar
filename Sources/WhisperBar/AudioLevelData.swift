import Foundation
import Combine

// MARK: - Audio Level Data

/// Observable store for real-time microphone amplitude samples.
/// The floating waveform view observes this object and redraws when levels change.
final class AudioLevelData: ObservableObject {

    /// Rolling buffer of normalised amplitude values [0, 1].
    /// Always kept at exactly `bufferSize` entries.
    @Published var levels: [Float]

    /// The most recently received amplitude (convenience).
    @Published var currentLevel: Float = 0

    let bufferSize: Int

    init(bufferSize: Int = 40) {
        self.bufferSize = bufferSize
        self.levels     = Array(repeating: 0, count: bufferSize)
    }

    // MARK: - API

    /// Append a new normalised level [0, 1] and drop the oldest sample.
    func push(_ level: Float) {
        // Must be called on the main thread (the publisher is @Published)
        assert(Thread.isMainThread)
        currentLevel = level
        levels.append(level)
        if levels.count > bufferSize { levels.removeFirst() }
    }

    /// Reset all samples to silence.
    func reset() {
        assert(Thread.isMainThread)
        currentLevel = 0
        levels = Array(repeating: 0, count: bufferSize)
    }
}
