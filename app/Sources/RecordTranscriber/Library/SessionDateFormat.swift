import Foundation

/// SessionDateFormat turns a start date into what a list row shows: `hoy 14:32`,
/// `ayer 09:10`, `28 ago 15:40`, or `28 ago 2025 15:40` once the year differs.
///
/// `now` is a parameter rather than a call to `Date()` inside, which is what
/// makes the labels assertable against literals in a test.
enum SessionDateFormat {
    /// monthNames are spelled out here instead of read from the locale because
    /// CLDR has changed its Spanish abbreviations between OS releases — both
    /// "sep" and "sept" ship — and a label that depends on the machine cannot be
    /// tested against a literal.
    private static let monthNames = [
        "ene", "feb", "mar", "abr", "may", "jun",
        "jul", "ago", "sep", "oct", "nov", "dic",
    ]

    static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute else { return "" }

        let time = String(format: "%02d:%02d", hour, minute)

        if calendar.isDate(date, inSameDayAs: now) { return "hoy \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "ayer \(time)"
        }

        let name = monthNames[month - 1]
        let currentYear = calendar.component(.year, from: now)
        if year == currentYear { return "\(day) \(name) \(time)" }
        return "\(day) \(name) \(year) \(time)"
    }
}
