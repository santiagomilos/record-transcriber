import Foundation
import Testing
@testable import RecordTranscriber

/// Each test gets its own defaults suite so nothing leaks between them or into
/// the real preferences.
private func isolatedPreferences() -> Preferences {
    let name = "record-transcriber-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return Preferences(defaults: defaults)
}

@Test func startsWithTheDocumentedDefaults() {
    let preferences = isolatedPreferences()
    #expect(preferences.language == "auto")
    #expect(preferences.formats == ["txt", "srt"])
    #expect(preferences.summaryKind == "minuta")
    #expect(preferences.model == "large-v3-turbo")
    #expect(preferences.libraryFolder.lastPathComponent == "Grabaciones")
}

@Test func rendersTheDefaultsAsTranscribeFlags() {
    let preferences = isolatedPreferences()

    let arguments = preferences.transcribeArguments(
        input: URL(fileURLWithPath: "/recordings/2026-09-01 0314/audio.opus"),
        outputBase: URL(fileURLWithPath: "/recordings/2026-09-01 0314/transcript"))

    #expect(arguments == [
        "-json",
        "-o", "/recordings/2026-09-01 0314/transcript",
        "-f", "txt,srt",
        "-l", "auto",
        "-m", "large-v3-turbo",
        "-summary", "minuta",
        "/recordings/2026-09-01 0314/audio.opus",
    ])
}

@Test func rendersChangedPreferencesAsTranscribeFlags() {
    let preferences = isolatedPreferences()
    preferences.language = "es"
    preferences.formats = ["txt", "srt", "vtt"]
    preferences.summaryKind = "none"
    preferences.model = "base"

    let arguments = preferences.transcribeArguments(
        input: URL(fileURLWithPath: "/tmp/a.opus"),
        outputBase: URL(fileURLWithPath: "/tmp/a"))

    #expect(arguments == [
        "-json",
        "-o", "/tmp/a",
        "-f", "txt,srt,vtt",
        "-l", "es",
        "-m", "base",
        "-summary", "none",
        "/tmp/a.opus",
    ])
}

@Test func persistsAChangeAcrossARelaunch() {
    let name = "record-transcriber-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!

    let first = Preferences(defaults: defaults)
    first.language = "en"
    first.summaryKind = "resumen"

    let second = Preferences(defaults: defaults)
    #expect(second.language == "en")
    #expect(second.summaryKind == "resumen")
}

@Test func formatsDurationsAsMinutesUntilAnHourPasses() {
    #expect(formatDuration(0) == "00:00")
    #expect(formatDuration(9) == "00:09")
    #expect(formatDuration(63) == "01:03")
    #expect(formatDuration(3599) == "59:59")
    #expect(formatDuration(3600) == "1:00:00")
    #expect(formatDuration(3723) == "1:02:03")
}
