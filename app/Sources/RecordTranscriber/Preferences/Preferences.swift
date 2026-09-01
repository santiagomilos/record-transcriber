import Foundation
import Observation

/// Preferences is what the user can configure, persisted in UserDefaults. It is
/// also the single place that knows how a preference becomes a `transcribe`
/// flag, so the mapping can be tested without running anything.
@Observable
final class Preferences {
    /// Defaults keys are stable: renaming one silently resets that preference
    /// for everyone who already has it set.
    private enum Key {
        static let libraryFolder = "libraryFolder"
        static let language = "language"
        static let formats = "formats"
        static let summaryKind = "summaryKind"
        static let model = "model"
    }

    static let languages = ["auto", "es", "en"]
    static let summaryKinds = ["none", "resumen", "minuta"]
    static let availableFormats = ["txt", "srt", "vtt"]
    static let defaultModel = "large-v3-turbo"

    /// defaultLibraryFolder is a plain folder in Documents, so a recording can
    /// be opened, moved or backed up without the app.
    static var defaultLibraryFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Grabaciones")
    }

    var libraryFolder: URL {
        didSet { defaults.set(libraryFolder.path, forKey: Key.libraryFolder) }
    }

    var language: String {
        didSet { defaults.set(language, forKey: Key.language) }
    }

    var formats: [String] {
        didSet { defaults.set(formats, forKey: Key.formats) }
    }

    var summaryKind: String {
        didSet { defaults.set(summaryKind, forKey: Key.summaryKind) }
    }

    var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Key.libraryFolder) {
            libraryFolder = URL(fileURLWithPath: path)
        } else {
            libraryFolder = Preferences.defaultLibraryFolder
        }
        language = defaults.string(forKey: Key.language) ?? "auto"
        formats = defaults.stringArray(forKey: Key.formats) ?? ["txt", "srt"]
        summaryKind = defaults.string(forKey: Key.summaryKind) ?? "minuta"
        model = defaults.string(forKey: Key.model) ?? Preferences.defaultModel
    }

    /// transcribeArguments renders the preferences as the flags
    /// `cmd/transcribe` accepts. The order is fixed so the result is testable,
    /// and the input path comes last because the CLI expects one bare argument.
    func transcribeArguments(input: URL, outputBase: URL) -> [String] {
        [
            "-json",
            "-o", outputBase.path,
            "-f", formats.joined(separator: ","),
            "-l", language,
            "-m", model,
            "-summary", summaryKind,
            input.path,
        ]
    }
}
