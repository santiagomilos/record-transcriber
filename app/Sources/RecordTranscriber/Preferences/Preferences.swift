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
        static let summaryKindMigratedToAuto = "summaryKindMigratedToAuto"
    }

    static let languages = ["auto", "es", "en"]
    static let summaryKinds = ["none", "auto", "resumen", "minuta"]
    static let availableFormats = ["txt", "srt", "vtt"]
    static let defaultModel = "large-v3-turbo"

    /// summaryKindNames are what the picker and the progress label show. The
    /// stored values stay as `cmd/transcribe` spells them.
    static let summaryKindNames = [
        "none": "Ninguno",
        "auto": "Automático",
        "resumen": "Resumen",
        "minuta": "Minuta",
    ]

    /// summaryKindName is the display name for a stored kind, falling back to
    /// the stored value so an unknown kind shows as itself rather than blank.
    static func summaryKindName(_ kind: String) -> String {
        summaryKindNames[kind] ?? kind
    }

    /// summaryKindProgressLabel is what the progress line calls the job while it
    /// runs. `auto` is not a word for the thing being written, so it borrows
    /// "resumen"; only `minuta` names its own output.
    static func summaryKindProgressLabel(_ kind: String) -> String {
        kind == "minuta" ? "minuta" : "resumen"
    }

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
        summaryKind = defaults.string(forKey: Key.summaryKind) ?? "auto"
        model = defaults.string(forKey: Key.model) ?? Preferences.defaultModel

        // `minuta` was the default before `auto` existed, so a stored `minuta`
        // is almost always the old default rather than a choice. Move it once
        // and record that, so choosing `minuta` again afterwards sticks.
        // The write is explicit because property observers do not fire for
        // assignments made during initialization.
        if !defaults.bool(forKey: Key.summaryKindMigratedToAuto) {
            defaults.set(true, forKey: Key.summaryKindMigratedToAuto)
            if summaryKind == "minuta" {
                summaryKind = "auto"
                defaults.set("auto", forKey: Key.summaryKind)
            }
        }
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
