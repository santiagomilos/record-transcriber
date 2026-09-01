import Foundation

/// OpusEncoder writes the captured audio as Opus by piping raw samples into
/// ffmpeg, which the project already depends on rather than linking an encoder.
///
/// 32 kbps mono is not a guess: measured on this project it costs 14 MB per hour
/// against 2.78 GB per hour for the screen captures it replaces, and the minutes
/// generated from it match those from the uncompressed original. Mono measured
/// better than stereo at the same bitrate, and doubling the bitrate changed the
/// transcript by less than one point.
final class OpusEncoder {
    static let bitrate = "32k"

    /// destination is the finished file. While recording, the encoder writes to
    /// `destination` plus ".part" and renames on a clean stop, so a crash never
    /// leaves a truncated file that looks ready to transcribe.
    let destination: URL
    private let partialURL: URL
    private let sampleRate: Double

    private let ring = PCMRingBuffer()
    private var process: Process?
    private var input: FileHandle?
    private var writer: Thread?
    private var isFinishing = false
    private var writeError: Error?

    init(destination: URL, sampleRate: Double) {
        self.destination = destination
        partialURL = destination.appendingPathExtension("part")
        self.sampleRate = sampleRate
    }

    var droppedFrames: Int { ring.droppedFrames }

    func start() throws {
        guard let ffmpeg = ToolPaths.locate("ffmpeg") else {
            throw RecordingError.missingTool("ffmpeg")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.environment = ToolPaths.childEnvironment
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "f32le", "-ar", String(Int(sampleRate)), "-ac", "1", "-i", "pipe:0",
            "-c:a", "libopus", "-b:a", Self.bitrate, "-application", "voip",
            // The part file's extension tells ffmpeg nothing, so the container
            // is named explicitly.
            "-f", "opus", partialURL.path,
        ]

        try process.run()
        self.process = process
        input = pipe.fileHandleForWriting

        let writer = Thread { [weak self] in self?.drain() }
        writer.name = "record-transcriber.encoder"
        writer.qualityOfService = .userInitiated
        writer.start()
        self.writer = writer
    }

    /// append is called from the audio thread and only touches the ring buffer.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        ring.write(samples)
    }

    /// finish drains what is left, closes ffmpeg's input, waits for it to write
    /// its trailer, and promotes the part file. It returns the finished file.
    @discardableResult
    func finish() throws -> URL {
        isFinishing = true
        while writer?.isFinished == false {
            Thread.sleep(forTimeInterval: 0.01)
        }
        try? input?.close()
        input = nil

        process?.waitUntilExit()
        let status = process?.terminationStatus ?? 0
        process = nil

        if let writeError { throw writeError }
        guard status == 0 else { throw RecordingError.encoderFailed(status) }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partialURL, to: destination)
        return destination
    }

    /// cancel abandons the recording and removes the partial file.
    func cancel() {
        isFinishing = true
        try? input?.close()
        input = nil
        process?.terminate()
        process = nil
        try? FileManager.default.removeItem(at: partialURL)
    }

    /// drain runs on its own thread so a slow write to ffmpeg never reaches the
    /// audio thread.
    private func drain() {
        let blockFrames = 4096
        var block = [Float](repeating: 0, count: blockFrames)

        while true {
            var moved = 0
            block.withUnsafeMutableBufferPointer { moved = ring.read(into: $0) }

            if moved == 0 {
                if isFinishing { return }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            do {
                try block.withUnsafeBufferPointer { buffer in
                    let data = Data(buffer: UnsafeBufferPointer(rebasing: buffer[0..<moved]))
                    try input?.write(contentsOf: data)
                }
            } catch {
                // ffmpeg died; stop writing rather than raising SIGPIPE on every
                // subsequent block. finish() reports it.
                writeError = error
                return
            }
        }
    }
}

/// RecordingError is what the UI shows when a recording cannot start or finish.
enum RecordingError: LocalizedError {
    case missingTool(String)
    case microphoneDenied
    case encoderFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .missingTool(name):
            return "\(name) is not installed."
        case .microphoneDenied:
            return "Record Transcriber needs microphone access. Grant it in System Settings › Privacy & Security › Microphone."
        case let .encoderFailed(status):
            return "ffmpeg exited with status \(status) while encoding the recording."
        }
    }
}
