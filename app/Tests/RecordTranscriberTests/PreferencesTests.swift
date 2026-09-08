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

/// A fixed instant, so the date name a test asserts never depends on when it
/// runs: 2026-09-01 03:14:15 local time.
private let importedAt: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 9
    components.day = 1
    components.hour = 3
    components.minute = 14
    components.second = 15
    return Calendar.current.date(from: components)!
}()

@Test func startsWithTheDocumentedDefaults() {
    let preferences = isolatedPreferences()
    #expect(preferences.language == "auto")
    #expect(preferences.formats == ["txt", "srt"])
    #expect(preferences.summaryKind == "auto")
    #expect(preferences.model == "large-v3-turbo")
    #expect(preferences.libraryFolder.lastPathComponent == "Grabaciones")
    #expect(preferences.importNaming == .fileName)
}

@Test func persistsTheImportNamingAcrossARelaunch() {
    let name = "record-transcriber-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!

    let first = Preferences(defaults: defaults)
    first.importNaming = .date

    let second = Preferences(defaults: defaults)
    #expect(second.importNaming == .date)
}

@Test func namesAnImportAfterItsFile() {
    let url = URL(fileURLWithPath: "/x/PTT-20260901-WA0003.opus")
    #expect(Preferences.ImportNaming.fileName.name(for: url, at: importedAt) == "PTT-20260901-WA0003")
}

@Test func namesAnImportAfterTheDate() {
    let url = URL(fileURLWithPath: "/x/PTT-20260901-WA0003.opus")
    #expect(Preferences.ImportNaming.date.name(for: url, at: importedAt) == "2026-09-01 0314")
}

@Test func fallsBackToTheDateForAFileWithNoStem() {
    let url = URL(fileURLWithPath: "/x/.opus")
    #expect(Preferences.ImportNaming.fileName.name(for: url, at: importedAt) == "2026-09-01 0314")
}

@Test func fallsBackToAutoWhenNoSummaryIsPreferred() {
    let preferences = isolatedPreferences()
    preferences.summaryKind = "none"
    #expect(preferences.onDemandSummaryKind == "auto")

    preferences.summaryKind = "minuta"
    #expect(preferences.onDemandSummaryKind == "minuta")
}

@Test func overridesTheSummaryKindForASummaryOnlyRun() {
    let preferences = isolatedPreferences()
    preferences.summaryKind = "none"

    let arguments = preferences.transcribeArguments(
        input: URL(fileURLWithPath: "/recordings/Archivos/PTT/transcript.srt"),
        outputBase: URL(fileURLWithPath: "/recordings/Archivos/PTT/transcript"),
        summaryKind: "auto")

    #expect(arguments == [
        "-json",
        "-o", "/recordings/Archivos/PTT/transcript",
        "-f", "txt,srt",
        "-l", "auto",
        "-m", "large-v3-turbo",
        "-summary", "auto",
        "/recordings/Archivos/PTT/transcript.srt",
    ])
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
        "-summary", "auto",
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

/// `minuta` was the default before `auto` existed, so an install carrying it is
/// almost certainly carrying the old default rather than a choice.
@Test func movesTheOldDefaultOntoAutoOnce() {
    let name = "record-transcriber-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.set("minuta", forKey: "summaryKind")

    let migrated = Preferences(defaults: defaults)
    #expect(migrated.summaryKind == "auto")
}

/// Choosing `minuta` again after the migration has run has to stick, which is
/// what the separate migration key buys.
@Test func leavesMinutaAloneOnceItHasBeenChosenAgain() {
    let name = "record-transcriber-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.set("minuta", forKey: "summaryKind")

    let migrated = Preferences(defaults: defaults)
    #expect(migrated.summaryKind == "auto")
    migrated.summaryKind = "minuta"

    let relaunched = Preferences(defaults: defaults)
    #expect(relaunched.summaryKind == "minuta")
}

/// A kind the user picked deliberately is never touched by the migration.
@Test func leavesADeliberateKindAlone() {
    let name = "record-transcriber-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.set("resumen", forKey: "summaryKind")

    let preferences = Preferences(defaults: defaults)
    #expect(preferences.summaryKind == "resumen")
}

@Test func namesEverySummaryKindItOffers() {
    for kind in Preferences.summaryKinds {
        #expect(Preferences.summaryKindName(kind) != kind)
    }
    #expect(Preferences.summaryKindName("auto") == "Automático")
    #expect(Preferences.summaryKindName("desconocido") == "desconocido")
}

/// `auto` is not a word for the thing being written, so the progress line calls
/// it a resumen while it runs.
@Test func callsTheRunningJobByWhatItProduces() {
    #expect(Preferences.summaryKindProgressLabel("auto") == "resumen")
    #expect(Preferences.summaryKindProgressLabel("resumen") == "resumen")
    #expect(Preferences.summaryKindProgressLabel("minuta") == "minuta")
}
