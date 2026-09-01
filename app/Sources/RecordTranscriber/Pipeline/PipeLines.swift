import Foundation

extension Pipe {
    /// lines streams what is written into the pipe one line at a time, finishing
    /// at end of file.
    ///
    /// Reading goes through `readabilityHandler`, which runs on a Dispatch queue
    /// of its own, rather than through `FileHandle.AsyncBytes`: AsyncBytes issues
    /// a blocking `read(2)` from a Swift concurrency cooperative thread, so a
    /// consumer that loses its thread stops draining the pipe, and the child
    /// process then deadlocks in `write(2)` as soon as the 64 KiB pipe buffer
    /// fills. That is what used to strand a transcription at 0%.
    ///
    /// `policy` bounds only what an outpaced consumer keeps; the pipe is drained
    /// at the same rate either way.
    func lines(
        buffering policy: AsyncStream<String>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<String> {
        let handle = fileHandleForReading
        return AsyncStream(bufferingPolicy: policy) { continuation in
            let splitter = LineSplitter()
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    if let last = splitter.flush() { continuation.yield(last) }
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                for line in splitter.take(chunk) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}

/// LineSplitter turns the arbitrary chunks a pipe hands over into whole lines.
///
/// It is unchecked-Sendable because a file handle serialises its readability
/// callbacks, so the instance is only ever touched from one of them at a time.
private final class LineSplitter: @unchecked Sendable {
    private var partial = Data()

    func take(_ chunk: Data) -> [String] {
        partial.append(chunk)
        var lines: [String] = []
        while let newline = partial.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: partial[partial.startIndex..<newline], as: UTF8.self))
            partial = Data(partial[partial.index(after: newline)...])
        }
        return lines
    }

    /// flush returns the final line when the stream ended without a newline.
    func flush() -> String? {
        guard !partial.isEmpty else { return nil }
        defer { partial = Data() }
        return String(decoding: partial, as: UTF8.self)
    }
}
