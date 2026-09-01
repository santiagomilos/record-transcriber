import Foundation
import Testing
@testable import RecordTranscriber

/// A calendar fixed to UTC, so a label never depends on where the test runs.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

/// now is 2026-09-01 18:00 UTC for every test in this file.
private let now = date(2026, 9, 1, 18, 0)

@Test func labelsARecordingFromTodayByItsTime() {
    let label = SessionDateFormat.label(for: date(2026, 9, 1, 14, 32), now: now, calendar: calendar)
    #expect(label == "hoy 14:32")
}

@Test func labelsARecordingFromYesterday() {
    let label = SessionDateFormat.label(for: date(2026, 8, 31, 9, 10), now: now, calendar: calendar)
    #expect(label == "ayer 09:10")
}

@Test func labelsAnOlderRecordingInTheSameYearWithoutTheYear() {
    let label = SessionDateFormat.label(for: date(2026, 8, 28, 15, 40), now: now, calendar: calendar)
    #expect(label == "28 ago 15:40")
}

@Test func labelsARecordingFromAnotherYearWithTheYear() {
    let label = SessionDateFormat.label(for: date(2025, 12, 24, 21, 5), now: now, calendar: calendar)
    #expect(label == "24 dic 2025 21:05")
}

@Test func labelsMidnightAsAZeroPaddedTime() {
    let label = SessionDateFormat.label(for: date(2026, 9, 1, 0, 0), now: now, calendar: calendar)
    #expect(label == "hoy 00:00")
}
