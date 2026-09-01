import Foundation

/// ToolPaths locates the external binaries the app drives.
///
/// An app launched from the Finder inherits `PATH=/usr/bin:/bin:/usr/sbin:/sbin`,
/// which does not contain Homebrew. Every subprocess the app spawns is therefore
/// given the PATH built here instead of the one it would inherit; without this
/// the app fails to find ffmpeg while the command line finds it fine.
enum ToolPaths {
    /// fallbackPaths are used when the login shell cannot be asked, and are
    /// appended to its PATH in every case.
    static let fallbackPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    /// searchPaths is the login shell's PATH followed by the fallbacks.
    ///
    /// A hardcoded list is not enough: Claude Code installs `claude` under
    /// ~/.local/bin, nowhere near Homebrew's prefix, and every user puts things
    /// somewhere slightly different. Asking the login shell is the only way to
    /// find what the user themselves can run. Computed once, on first use.
    static let searchPaths: [String] = {
        var seen = Set<String>()
        return (loginShellPaths() + fallbackPaths).filter { seen.insert($0).inserted }
    }()

    /// loginShellPaths asks the user's login shell what PATH it sets up. It
    /// returns nothing rather than failing: the fallbacks still cover Homebrew.
    private static func loginShellPaths() -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l so the shell reads the profile that sets PATH, -c so it then exits.
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// childPATH is the PATH handed to every subprocess.
    static var childPATH: String { searchPaths.joined(separator: ":") }

    /// childEnvironment is the process environment with PATH replaced.
    static var childEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = childPATH
        return environment
    }

    /// locate returns the full path of an installed binary, or nil.
    static func locate(_ binary: String) -> String? {
        for directory in searchPaths {
            let candidate = directory + "/" + binary
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// transcribe is the Go binary shipped inside the bundle, so the app never
    /// depends on the user having installed it separately.
    static var transcribe: URL? {
        Bundle.main.url(forResource: "transcribe", withExtension: nil)
    }
}

/// Tool is an external binary the app needs, paired with how to install it.
struct Tool: Identifiable, Hashable {
    let binary: String
    let installCommand: String
    /// required is false for tools that only disable a feature when missing.
    let required: Bool

    var id: String { binary }
    var isInstalled: Bool { ToolPaths.locate(binary) != nil }

    static let ffmpeg = Tool(binary: "ffmpeg", installCommand: "brew install ffmpeg", required: true)
    static let ffprobe = Tool(binary: "ffprobe", installCommand: "brew install ffmpeg", required: true)
    static let whisper = Tool(binary: "whisper-cli", installCommand: "brew install whisper-cpp", required: true)
    static let claude = Tool(binary: "claude", installCommand: "npm install -g @anthropic-ai/claude-code", required: false)

    /// all is checked at launch, matching the CLI's fail-fast ordering: a
    /// missing dependency is reported before any recording is made, not after.
    static let all = [ffmpeg, ffprobe, whisper, claude]

    static var missing: [Tool] { all.filter { !$0.isInstalled } }
    static var missingRequired: [Tool] { missing.filter(\.required) }
}
