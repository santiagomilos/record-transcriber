import SwiftUI

/// SessionDetailView shows what one recording produced.
struct SessionDetailView: View {
    @Bindable var model: AppModel
    let session: Session

    private enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Transcripción"
        case summary = "Resumen"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .summary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.runner.isRunning {
                PhaseProgress(phase: model.runner.phase)
                    .padding(.horizontal, Theme.panelPadding + Theme.Space.sm)
                    .padding(.bottom, Theme.Space.md)
            }

            tabs
                .padding(.horizontal, Theme.panelPadding + Theme.Space.sm)
                .padding(.bottom, Theme.Space.md)

            content
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                StatusBadge(status: session.status)
                Spacer()

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

    /// facts is the metadata line under the title: how long the recording is,
    /// what language it turned out to be, how many segments the transcript has.
    /// It is nil for a session recorded before the sidecar existed.
    private var facts: String? {
        guard let metadata = session.metadata else { return nil }
        var parts: [String] = []
        if metadata.durationSeconds > 0 { parts.append(formatDuration(metadata.durationSeconds)) }
        if let language = metadata.language, !language.isEmpty { parts.append("idioma \(language)") }
        if metadata.segments > 0 { parts.append("\(metadata.segments) segmentos") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(Theme.rowTitleFont)
                        .foregroundStyle(tab == candidate ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.sm)
                        .background(tab == candidate ? Theme.rowHover : .clear,
                                    in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(3)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        let text = tab == .transcript ? session.transcriptText : session.summaryText
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
                Text(session.hasAudio
                    ? "Usa el botón de recargar para generarla."
                    : "Esta grabación no tiene audio.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
