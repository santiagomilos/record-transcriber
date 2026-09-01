import SwiftUI

/// Theme is the only place in the app that names a raw color or a layout
/// constant. A view that writes a literal instead of a token here is how a
/// design drifts.
///
/// The palette is fixed rather than following the system appearance: the panel
/// stays dark in Light Mode. That is a deliberate trade — it buys the app one
/// look everywhere, and costs a theme that has to be maintained by hand.
enum Theme {
    // MARK: Palette

    /// panelTop and panelBottom are the vertical gradient behind the panel,
    /// sampled from `visuals/toolbox-reference.png`: a warm plum at the header
    /// falling to the dark the content sits on.
    static let panelTop = Color(red: 0.322, green: 0.200, blue: 0.306)
    static let panelBottom = Color(red: 0.176, green: 0.137, blue: 0.216)

    static let cardBackground = Color(red: 0.200, green: 0.157, blue: 0.251)
    static let cardBorder = Color(red: 0.231, green: 0.200, blue: 0.267)
    /// tooltipBackground is darker than a card so a tooltip reads as floating
    /// above the panel rather than as one more block in it.
    static let tooltipBackground = Color(red: 0.106, green: 0.078, blue: 0.137)
    /// rowHover is layered over whatever is behind it, so it is an overlay
    /// rather than a solid.
    static let rowHover = Color.white.opacity(0.07)
    static let rowPressed = Color.white.opacity(0.12)

    static let textPrimary = Color(red: 0.847, green: 0.843, blue: 0.851)
    static let textSecondary = Color(red: 0.612, green: 0.573, blue: 0.659)
    static let textTertiary = Color(red: 0.431, green: 0.408, blue: 0.447)

    /// accent and recording are the two ends of the reference's brand gradient:
    /// the magenta it runs into, and the coral it starts from. They are kept far
    /// enough apart in hue that a running recording never reads as an ordinary
    /// control.
    static let accent = Color(red: 0.788, green: 0.318, blue: 0.757)
    static let recording = Color(red: 0.941, green: 0.357, blue: 0.427)
    static let warning = Color(red: 0.910, green: 0.639, blue: 0.239)
    static let success = Color(red: 0.290, green: 0.769, blue: 0.494)

    /// brandGradient is the reference's own mark gradient, coral running into
    /// magenta. It belongs to the header mark and nothing else: a gradient that
    /// appears twice stops reading as an identity.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [recording, accent],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    /// panelGradient holds the plum across the header and has resolved to the
    /// dark by roughly a third of the way down, which is where the reference
    /// puts the transition. A gradient spread over the whole height instead
    /// washes the content rows out.
    static var panelGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: panelTop, location: 0),
            .init(color: panelTop, location: 0.12),
            .init(color: panelBottom, location: 0.38),
            .init(color: panelBottom, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Metrics

    /// panelWidth is wide enough for a recording label plus its duration and
    /// badge on one line, which is what sets it.
    static let panelWidth: CGFloat = 320
    static let panelPadding: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let rowRadius: CGFloat = 7
    static let rowPadding: CGFloat = 8

    /// tooltipDelay is shorter than the system's roughly two seconds. These
    /// tooltips label icon-only buttons, so waiting is waiting to find out what
    /// a button does.
    static let tooltipDelay = Duration.milliseconds(350)

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    // MARK: Typography

    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let rowTitleFont = Font.system(size: 12.5, weight: .medium)
    static let bodyFont = Font.system(size: 12)
    static let captionFont = Font.system(size: 11)
    static let badgeFont = Font.system(size: 10, weight: .medium)
    /// sectionFont is the uppercase label above a group, as in the reference.
    static let sectionFont = Font.system(size: 10, weight: .semibold)
    /// timerFont is monospaced so the elapsed time does not jitter as digits
    /// change width.
    static let timerFont = Font.system(size: 15, weight: .semibold).monospacedDigit()
}
