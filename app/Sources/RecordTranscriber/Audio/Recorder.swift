import AVFoundation
import Foundation
import Observation

/// Recorder drives one capture from start to finished Opus file.
///
/// Permission is requested with async/await rather than by waiting on a
/// semaphore. macOS presents the prompt through the main run loop, so blocking
/// that run loop means the prompt never appears and the app hangs with nothing
/// on screen.
@MainActor
@Observable
final class Recorder {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case finishing
    }

    private(set) var state: State = .idle
    private(set) var levels = AudioCapture.Levels()
    private(set) var elapsed: TimeInterval = 0

    var isRecording: Bool { state == .recording }

    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var encoder: OpusEncoder?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var meter: Timer?

    /// start begins capturing into destination. It throws before touching any
    /// hardware when the microphone is unavailable or ffmpeg is missing, so a
    /// failed start never leaves a half-open device behind.
    func start(writingTo destination: URL) async throws {
        guard state == .idle else { return }
        state = .starting

        guard await Recorder.requestMicrophoneAccess() else {
            state = .idle
            throw RecordingError.microphoneDenied
        }

        let capture = AudioCapture()
        do {
            try capture.start()
        } catch {
            state = .idle
            throw error
        }

        let encoder = OpusEncoder(destination: destination, sampleRate: capture.sampleRate)
        do {
            try encoder.start()
        } catch {
            capture.stop()
            state = .idle
            throw error
        }

        capture.onAudio = { [weak encoder] samples in encoder?.append(samples) }

        self.capture = capture
        self.encoder = encoder
        startedAt = Date()
        elapsed = 0
        state = .recording
        startMeter()
    }

    /// stop finishes the recording and returns the Opus file.
    func stop() async throws -> URL {
        guard state == .recording, let capture, let encoder else {
            throw RecordingError.encoderFailed(0)
        }
        state = .finishing
        stopMeter()

        // Order matters: the capture stops feeding the ring buffer before the
        // encoder drains it, so nothing is written after ffmpeg's input closes.
        capture.stop()
        self.capture = nil

        defer {
            self.encoder = nil
            startedAt = nil
            state = .idle
            levels = AudioCapture.Levels()
        }
        return try encoder.finish()
    }

    /// cancel abandons a recording in progress and removes its partial file.
    func cancel() {
        stopMeter()
        capture?.stop()
        capture = nil
        encoder?.cancel()
        encoder = nil
        startedAt = nil
        elapsed = 0
        levels = AudioCapture.Levels()
        state = .idle
    }

    private func startMeter() {
        // 20 Hz: fast enough for a level meter to look live, slow enough that
        // the main thread is not redrawing constantly through a long meeting.
        meter = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    private func stopMeter() {
        meter?.invalidate()
        meter = nil
    }

    private func sample() {
        guard let capture, let startedAt else { return }
        levels = capture.levels

        // The meter runs at 20 Hz but elapsed is only written when its whole
        // second changes: the menu bar icon observes it, and a status item
        // redrawn twenty times a second for a value that reads the same is work
        // nobody sees.
        let now = Date().timeIntervalSince(startedAt)
        if Int(now) != Int(elapsed) { elapsed = now }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        default:
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
}
