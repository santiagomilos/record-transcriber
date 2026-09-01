import SwiftUI

/// MenuBarView is the control that is reachable while another app is in the
/// foreground, which is where recording actually starts and stops. It is also
/// the only place Preferences can be opened from, since the app has no menu bar
/// of its own.
struct MenuBarView: View {
    /// recentCount is how many recordings the panel lists before deferring to
    /// the window. Five keeps the panel one screen tall.
    private static let recentCount = 5

    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    /// Preferences replace the panel's content instead of opening a window of
    /// their own: a menu bar app that throws a separate window at you for four
    /// settings has left the menu bar.
    @State private var showingPreferences = false

    var body: some View {
        Group {
            if showingPreferences {
                PreferencesView(model: model) { showingPreferences = false }
            } else {
                home
            }
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.panelWidth)
        .background(Theme.panelGradient)
        .environment(\.colorScheme, .dark)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
                // The header's tooltips hang below it, over the card that
                // follows, which draws later in the stack unless lifted.
                .zIndex(1)
            state

            // The window carries the same message in an alert, but it is often
            // closed while recording, and a failure nobody sees is a failure
            // that looks like nothing happening at all.
            if let failure = model.failure {
                Banner(icon: "exclamationmark.triangle.fill", message: failure) {
                    Button("Descartar") { model.failure = nil }
                        .buttonStyle(.plain)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.accent)
                }
            }

            if !model.missingTools.filter(\.required).isEmpty {
                Banner(icon: "shippingbox.fill", message: "Faltan dependencias para transcribir.") {
                    Button("Ver cuáles") { openLibrary() }
                        .buttonStyle(.plain)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.accent)
                }
            }

            recents
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            BrandMark()
            Text("Record Transcriber")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            IconButton(icon: "gearshape", help: "Preferencias") {
                showingPreferences = true
            }
            .keyboardShortcut(",")

            IconButton(icon: "power", help: "Salir") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.Space.xs)
    }

    // MARK: State card

    @ViewBuilder private var state: some View {
        if model.recorder.isRecording {
            PanelCard(padding: Theme.Space.md) {
                HStack(spacing: Theme.Space.md) {
                    Circle()
                        .fill(Theme.recording)
                        .frame(width: 9, height: 9)
                        .symbolEffectFallbackPulse()
                    Text("Grabando")
                        .font(Theme.rowTitleFont)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatDuration(model.recorder.elapsed))
                        .font(Theme.timerFont)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.bottom, Theme.Space.xs)

                LevelMeter(levels: model.recorder.levels)
                    .padding(.bottom, Theme.Space.sm)

                HStack(spacing: Theme.Space.sm) {
                    Button("Detener") { Task { await model.stopRecording() } }
                        .buttonStyle(FilledButtonStyle(tint: Theme.recording))
                        .keyboardShortcut("r")
                    Button("Descartar") { model.cancelRecording() }
                        .buttonStyle(FilledButtonStyle(tint: Theme.textSecondary, isProminent: false))
                }
            }
        } else if model.runner.isRunning {
            PanelCard(padding: Theme.Space.md) {
                PhaseProgress(phase: model.runner.phase)
            }
        } else {
            PanelCard(padding: Theme.Space.xs) {
                PanelRow(icon: "record.circle",
                         title: "Grabar",
                         subtitle: "Micrófono + sistema",
                         iconColor: Theme.recording,
                         isEnabled: !model.isBusy) {
                    Task { await model.startRecording() }
                } trailing: {
                    Text("⌘R")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                .keyboardShortcut("r")
            }
        }
    }

    // MARK: Recent recordings

    private var recents: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionLabel(text: "Recientes")
                .padding(.horizontal, Theme.Space.xs)

            PanelCard(padding: Theme.Space.xs) {
                if model.library.sessions.isEmpty {
                    Text("Todavía no hay grabaciones.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.rowPadding)
                        .padding(.vertical, Theme.Space.sm)
                } else {
                    ForEach(model.library.sessions.prefix(Self.recentCount)) { session in
                        PanelRow(icon: "waveform",
                                 title: session.displayName,
                                 subtitle: subtitle(for: session)) {
                            openLibrary(selecting: session)
                        } trailing: {
                            StatusBadge(status: session.status)
                        }
                    }
                }
            }
        }
    }

    /// subtitle is the second line of a recording row: its length, and the
    /// language once the pipeline has detected one. A session recorded before
    /// the metadata sidecar existed has neither, and shows nothing.
    private func subtitle(for session: Session) -> String? {
        guard let metadata = session.metadata else { return nil }
        var parts: [String] = []
        if metadata.durationSeconds > 0 { parts.append(formatDuration(metadata.durationSeconds)) }
        if let language = metadata.language, !language.isEmpty { parts.append(language) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Footer

    private var footer: some View {
        PanelRow(icon: "rectangle.stack",
                 title: "Abrir biblioteca") {
            openLibrary()
        } trailing: {
            Text("⌘O")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .keyboardShortcut("o")
    }

    /// openLibrary brings the window to the front. An accessory app is never
    /// activated on its own, so without the explicit activation the window opens
    /// behind whatever the user was looking at.
    private func openLibrary(selecting session: Session? = nil) {
        if let session { model.selection = session.id }
        activate()
        openWindow(id: LibraryWindow.id)
    }

    private func activate() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private extension View {
    /// symbolEffectFallbackPulse animates the recording dot. It is a plain
    /// opacity animation rather than `.symbolEffect` because the dot is a shape,
    /// not a symbol.
    func symbolEffectFallbackPulse() -> some View {
        modifier(PulseModifier())
    }
}

private struct PulseModifier: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}
