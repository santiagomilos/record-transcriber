import Foundation
import os

/// PCMRingBuffer hands samples from the audio thread to the encoder thread.
///
/// The audio callback cannot block, so it never waits for the encoder: when the
/// buffer is full the oldest samples are dropped and counted. Dropping is the
/// lesser evil, because stalling the audio thread corrupts the capture rather
/// than delaying it. At 48 kHz mono the default capacity holds ten seconds,
/// which ffmpeg has never needed even on a loaded machine.
final class PCMRingBuffer {
    private struct State {
        var readIndex = 0
        var writeIndex = 0
        var count = 0
        var dropped = 0
    }

    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private var state = State()
    private let lock = UnfairLock()

    init(capacity: Int = 48000 * 10) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// droppedFrames is how many samples were discarded because the encoder
    /// could not keep up. Anything above zero means the recording has a gap.
    var droppedFrames: Int { lock.locked { state.dropped } }

    /// write copies a block in. Called from the audio thread.
    func write(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, !samples.isEmpty else { return }
        lock.locked {
            let writable = min(samples.count, capacity - state.count)
            if writable < samples.count {
                state.dropped += samples.count - writable
            }
            for index in 0..<writable {
                storage[(state.writeIndex + index) % capacity] = base[index]
            }
            state.writeIndex = (state.writeIndex + writable) % capacity
            state.count += writable
        }
    }

    /// read moves up to `into.count` samples out, returning how many it moved.
    /// Called from the encoder thread.
    func read(into destination: UnsafeMutableBufferPointer<Float>) -> Int {
        guard let base = destination.baseAddress else { return 0 }
        return lock.locked {
            let readable = min(destination.count, state.count)
            for index in 0..<readable {
                base[index] = storage[(state.readIndex + index) % capacity]
            }
            state.readIndex = (state.readIndex + readable) % capacity
            state.count -= readable
            return readable
        }
    }

    var isEmpty: Bool { lock.locked { state.count == 0 } }
}
