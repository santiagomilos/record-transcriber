import Foundation

/// SummaryAvailability says whether a summary can be produced, and if not, why.
///
/// A summary runs `claude --print --restricted` (see `claudeArgs` in
/// internal/summary/summary.go). Nothing runs that command until a summary is
/// asked for, so a `claude` that renamed the flag would otherwise fail after the
/// decode was already paid for. The check reads `claude --help` once.
enum SummaryAvailability: Equatable {
    case checking
    case available
    case claudeMissing
    case restrictedUnsupported
    case helpUnreadable

    /// allowsSummaries is false only when summaries are known not to work. A
    /// check still running, or one that could not read `claude --help`, proves
    /// nothing, and `claude` may well work.
    var allowsSummaries: Bool {
        switch self {
        case .claudeMissing, .restrictedUnsupported: return false
        case .checking, .available, .helpUnreadable: return true
        }
    }

    /// reason is the user-facing explanation, nil when nothing is wrong.
    var reason: String? {
        switch self {
        case .checking, .available:
            return nil
        case .claudeMissing:
            return "Los resúmenes no están disponibles: no se encontró Claude Code."
        case .restrictedUnsupported:
            return "Los resúmenes no están disponibles: esta versión de Claude Code no admite --restricted. Actualízala."
        case .helpUnreadable:
            return "No se pudo comprobar la versión de Claude Code (claude --help). Los resúmenes pueden fallar."
        }
    }

    /// evaluate decides from the output of `claude --help`, nil when it could
    /// not be run. A longer flag such as `--restricted-mode` does not count.
    static func evaluate(helpOutput: String?) -> SummaryAvailability {
        guard let helpOutput else { return .helpUnreadable }
        let lists = helpOutput.range(of: #"--restricted(?![\w-])"#, options: .regularExpression) != nil
        return lists ? .available : .restrictedUnsupported
    }

    /// check runs `claude --help` and blocks until it exits, so call it off the
    /// main thread.
    static func check() -> SummaryAvailability {
        guard let claude = ToolPaths.locate(Tool.claude.binary) else { return .claudeMissing }
        return evaluate(helpOutput: helpOutput(of: claude))
    }

    /// helpTimeout bounds the check: a `claude` that hangs on --help must not
    /// leave summaries stuck on "checking".
    private static let helpTimeout: TimeInterval = 10

    private static func helpOutput(of binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--help"]
        process.environment = ToolPaths.childEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        // The read runs off this thread so the deadline bounds it: a child of
        // `claude` that keeps stdout open would otherwise hold `readToEnd` past
        // the timeout even after `claude` itself was terminated.
        let output = HelpOutput()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue.global().async {
            output.data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            read.leave()
        }
        guard read.wait(timeout: .now() + helpTimeout) == .success else {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        let data = output.data

        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// HelpOutput carries the bytes from the reading thread; it is written once,
    /// before the group is left, and read only after the wait succeeded.
    private final class HelpOutput: @unchecked Sendable {
        var data = Data()
    }
}
