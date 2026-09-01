import SwiftUI

/// PanelCard groups related controls the way the reference does: a filled,
/// bordered block rather than items separated by dividers.
struct PanelCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.sm
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

/// BrandMark is the app's mark in the panel header: a white glyph on the brand
/// gradient, the shape the reference uses.
///
/// The glyph is white rather than tinted because the mark sits on the plum
/// header, where an accent-colored symbol on an accent-colored tile has nothing
/// to contrast against.
struct BrandMark: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.brandGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white))
    }
}

/// BackLink returns to the panel's first screen, the way out of anything the
/// header opens in place.
struct BackLink: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(Theme.rowTitleFont)
            }
            .foregroundStyle(isHovering ? Theme.textPrimary : Theme.accent)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// SectionLabel is the quiet header above a group.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sectionFont)
            .kerning(0.6)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// PanelRow is the one clickable row shape in the app, used for the panel's
/// actions, its recent recordings, and the window's sidebar. One component
/// rather than three views that drift apart.
struct PanelRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    /// A row's icon reads at the weight of its title, not of its subtitle: it
    /// names the action, and the reference keeps the same split — bright for
    /// what you act on, muted for what merely describes it.
    var iconColor: Color = Theme.textPrimary
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isEnabled ? iconColor : Theme.textTertiary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.rowTitleFont)
                        .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing
            }
            .padding(.horizontal, Theme.rowPadding)
            .padding(.vertical, subtitle == nil ? 7 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return Theme.accent.opacity(0.22) }
        return isHovering && isEnabled ? Theme.rowHover : .clear
    }
}

extension PanelRow where Trailing == EmptyView {
    init(icon: String,
         title: String,
         subtitle: String? = nil,
         iconColor: Color = Theme.textPrimary,
         isSelected: Bool = false,
         isEnabled: Bool = true,
         action: @escaping () -> Void) {
        self.init(icon: icon,
                  title: title,
                  subtitle: subtitle,
                  iconColor: iconColor,
                  isSelected: isSelected,
                  isEnabled: isEnabled,
                  action: action) { EmptyView() }
    }
}

/// StatusBadge says how far a recording got, so a row does not need three icons
/// to spell out which files exist.
struct StatusBadge: View {
    let status: Session.Status

    var body: some View {
        Text(text)
            .font(Theme.badgeFont)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var text: String {
        switch status {
        case .capturing: return "en curso"
        case .empty: return "vacía"
        case .needsTranscription: return "sin transcribir"
        case .ready: return "transcrita"
        case .complete: return "lista"
        }
    }

    private var color: Color {
        switch status {
        case .capturing: return Theme.recording
        case .empty: return Theme.textTertiary
        case .needsTranscription: return Theme.warning
        case .ready: return Theme.accent
        case .complete: return Theme.success
        }
    }
}

/// LevelMeter shows both sources separately. Two bars rather than one is
/// deliberate: the common failure is capturing only your own voice, and a single
/// mixed bar hides it.
struct LevelMeter: View {
    let levels: AudioCapture.Levels

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            bar(label: "Micrófono", level: levels.microphone)
            bar(label: "Sistema", level: levels.system)
        }
    }

    private func bar(label: String, level: Float) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 58, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(level > 0.001 ? Theme.accent : Theme.textTertiary)
                        .frame(width: geometry.size.width * CGFloat(displayLevel(level)))
                }
            }
            .frame(height: 5)
        }
    }

    /// displayLevel maps the peak onto a decibel-ish curve, because a linear bar
    /// spends most of its length on levels nobody records at.
    private func displayLevel(_ level: Float) -> Float {
        guard level > 0.0001 else { return 0 }
        let decibels = 20 * log10(level)
        return min(1, max(0, (decibels + 60) / 60))
    }
}

/// PhaseProgress renders one pipeline phase: its label, its bar, and the
/// percentage when the phase knows one.
struct PhaseProgress: View {
    let phase: TranscribeRunner.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text(phase.label)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let fraction = phase.fraction {
                    Text("\(Int(fraction * 100))%")
                        .font(Theme.captionFont.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ProgressView(value: phase.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
        }
    }
}

/// Banner carries a message the user has to see — a failure, or a missing
/// dependency — in the panel's own idiom rather than a system alert.
struct Banner<Actions: View>: View {
    let icon: String
    let message: String
    var tint: Color = Theme.warning
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(message)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.md)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1))
    }
}

/// FilledButtonStyle is the panel's own button: the system's bordered style
/// paints itself from the system appearance, which the panel does not follow.
struct FilledButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var isProminent = true

    func makeBody(configuration: Configuration) -> some View {
        // The hover state and the enabled flag live in a view rather than in the
        // style: a ButtonStyle is a value SwiftUI recreates, so @State and
        // @Environment declared on it have nowhere to live.
        FilledButtonBody(configuration: configuration, tint: tint, isProminent: isProminent)
    }
}

private struct FilledButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let isProminent: Bool

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Theme.rowTitleFont)
            .foregroundStyle(foreground)
            // The padding comes before the frame so a button sized to its label
            // still has room around the text: with only the full-width frame,
            // `fixedSize` collapsed it onto the letters.
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowRadius)
                    .strokeBorder(isProminent ? .clear : Theme.cardBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
            .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.textTertiary }
        return isProminent ? .white : tint
    }

    private var background: Color {
        guard isEnabled else { return Color.white.opacity(0.05) }
        if isProminent {
            return tint.opacity(configuration.isPressed ? 0.75 : (isHovering ? 0.90 : 1))
        }
        return configuration.isPressed ? Theme.rowPressed : (isHovering ? Theme.rowHover : .clear)
    }
}

/// IconButton is the small square control used in the panel header.
struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                // The icon is bright at rest, as it is in the reference;
                // hovering is signalled by the background rather than by
                // lifting the color further.
                .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(isHovering && isEnabled ? Theme.rowHover : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .tooltip(help)
    }
}

/// CopyButton puts text on the pasteboard and shows that it did.
///
/// The acknowledgement is the point: a copy leaves the screen looking exactly as
/// it did before, so without one the user cannot tell a press that worked from
/// a press that missed, and presses again.
struct CopyButton: View {
    let text: String
    var help = "Copiar"

    /// howLongToConfirm outlasts a glance at the button without lingering long
    /// enough to read as the control's resting state.
    private static let howLongToConfirm = Duration.seconds(1.5)

    @State private var didCopy = false
    @State private var revert: Task<Void, Never>?

    var body: some View {
        IconButton(icon: didCopy ? "checkmark" : "doc.on.doc",
                   help: didCopy ? "Copiado" : help) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            didCopy = true
            revert?.cancel()
            revert = Task {
                try? await Task.sleep(for: Self.howLongToConfirm)
                guard !Task.isCancelled else { return }
                didCopy = false
            }
        }
    }
}

extension View {
    /// tooltip labels an icon-only button. It replaces `.help`, whose bubble is
    /// drawn by the system in the system's appearance and after the system's
    /// long delay — both wrong for a panel that paints its own.
    func tooltip(_ text: String) -> some View { modifier(TooltipModifier(text: text)) }
}

private struct TooltipModifier: ViewModifier {
    let text: String

    @State private var isShowing = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                pending?.cancel()
                guard isHovering else {
                    isShowing = false
                    return
                }
                pending = Task {
                    try? await Task.sleep(for: Theme.tooltipDelay)
                    guard !Task.isCancelled else { return }
                    isShowing = true
                }
            }
            .overlay(alignment: .top) {
                if isShowing {
                    Text(text)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize()
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, Theme.Space.xs)
                        .background(Theme.tooltipBackground,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.cardBorder, lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        // The bubble hangs below the button it labels, and must
                        // never eat the click it is explaining.
                        .offset(y: 28)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isShowing)
    }
}
