import SwiftUI

/// SessionDetailView shows what one recording produced.
struct SessionDetailView: View {
    @Bindable var model: AppModel
    let session: Session
    /// onRename asks the window to open its rename field for this session; the
    /// field lives there because the row's context menu opens the same one.
    let onRename: (Session) -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Transcripción"
        case summary = "Resumen"
        var id: String { rawValue }
    }

    @State private var tab: Tab

    init(model: AppModel, session: Session, onRename: @escaping (Session) -> Void) {
        self.model = model
        self.session = session
        self.onRename = onRename
        // An import has no summary until asked for one, so opening on an empty
        // summary tab would show a placeholder where the transcript is.
        _tab = State(initialValue: session.hasSummary ? .summary : .transcript)
    }

    var body: some View {
        // Read once and hand it to both halves: the properties behind it open
        // the file, and this view redraws on every hover.
        let text = activeText

        VStack(alignment: .leading, spacing: 0) {
            header

            if model.runner.isRunning {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    PhaseProgress(phase: model.runner.phase)
                    if let progress = model.importProgress {
                        Text("Archivo \(min(progress.done + 1, progress.total)) de \(progress.total)")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, Theme.panelPadding + Theme.Space.sm)
                .padding(.bottom, Theme.Space.md)
            }

            tabs(copyable: text)
                .padding(.horizontal, Theme.panelPadding + Theme.Space.sm)
                .padding(.bottom, Theme.Space.md)

            content(text: text)
        }
    }

    /// activeText is what the selected tab shows, and what its copy button puts
    /// on the pasteboard.
    private var activeText: String? {
        tab == .transcript ? session.transcriptText : session.summaryText
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatusBadge(status: session.status)
                Spacer()

                if session.summarizableTranscriptURL != nil {
                    Button(session.hasSummary ? "Resumir de nuevo" : "Resumir") {
                        Task { await model.summarize(session) }
                    }
                    .buttonStyle(FilledButtonStyle(isProminent: !session.hasSummary))
                    .fixedSize()
                    .disabled(model.isBusy || claudeIsMissing)
                }

                IconButton(icon: "pencil", help: "Renombrar") {
                    onRename(session)
                }
                .disabled(model.isBusy)

                IconButton(icon: "arrow.clockwise", help: "Transcribir de nuevo") {
                    Task { await model.transcribe(session) }
                }
                .disabled(model.isBusy || !session.hasAudio)

                IconButton(icon: "folder", help: "Mostrar en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([session.folder])
                }
            }

            if let facts = facts {
                Text(facts)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.panelPadding + Theme.Space.sm)
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.lg)
    }

    /// A summary is a `claude` run, so the button that asks for one is disabled
    /// rather than failing after the click when the tool is not installed.
    private var claudeIsMissing: Bool {
        model.missingTools.contains { $0.binary == Tool.claude.binary }
    }

    /// facts is the metadata line under the title: the file an import came
    /// from, how long the recording is, what language it turned out to be, how
    /// many segments the transcript has. It is nil for a session recorded
    /// before the sidecar existed.
    private var facts: String? {
        guard let metadata = session.metadata else { return nil }
        var parts: [String] = []
        if let source = metadata.sourceName, !source.isEmpty { parts.append(source) }
        if metadata.durationSeconds > 0 { parts.append(formatDuration(metadata.durationSeconds)) }
        if let language = metadata.language, !language.isEmpty { parts.append("idioma \(language)") }
        if metadata.segments > 0 { parts.append("\(metadata.segments) segmentos") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: Tabs

    private func tabs(copyable text: String?) -> some View {
        TabStrip(items: Tab.allCases, title: \.rawValue, selection: $tab) {
            // The button sits with the tabs rather than in the header because it
            // copies the tab that is open, not the session.
            if let text, !text.isEmpty {
                CopyButton(text: text, help: "Copiar \(tab.rawValue.lowercased())")
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(text: String?) -> some View {
        if let text, !text.isEmpty {
            ScrollView {
                Group {
                    if tab == .summary {
                        MarkdownText(markdown: text)
                    } else {
                        Text(text)
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.panelPadding + Theme.Space.sm)
                .padding(.bottom, Theme.Space.lg)
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder private var placeholder: some View {
        VStack(spacing: Theme.Space.sm) {
            if model.runner.isRunning {
                Text("Procesando")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(tab == .transcript ? "Sin transcripción" : "Sin resumen")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                Text(placeholderHint)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderHint: String {
        if !session.hasAudio { return "Esta grabación no tiene audio." }
        if tab == .summary, session.summarizableTranscriptURL != nil {
            return "Pulsa Resumir para generarlo."
        }
        return "Usa el botón de recargar para generarla."
    }
}
