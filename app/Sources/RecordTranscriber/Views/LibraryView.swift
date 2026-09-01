import SwiftUI
import UniformTypeIdentifiers

enum LibraryWindow {
    static let id = "library"
}

/// LibraryView is the window: the list of recordings on the left, whatever the
/// selected one produced on the right.
struct LibraryView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .background(Theme.panelBottom)
            Divider().overlay(Theme.cardBorder)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panelGradient)
        }
        .onDrop(of: [.audio, .movie, .mpeg4Movie], isTargeted: nil, perform: handleDrop)
        .alert("No se pudo completar", isPresented: showingFailure) {
            Button("Entendido", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
        .task { model.recheckTools() }
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.md) {
                SectionLabel(text: "Grabaciones")
                Spacer()
                recordButton
            }
            .padding(.horizontal, Theme.panelPadding)
            .padding(.vertical, Theme.Space.md)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !model.missingTools.filter(\.required).isEmpty {
                        MissingToolsView(tools: model.missingTools) { model.recheckTools() }
                            .padding(.bottom, Theme.Space.md)
                    }

                    if model.library.sessions.isEmpty {
                        emptyLibrary
                    } else {
                        ForEach(model.library.sessions) { session in
                            PanelRow(icon: "waveform",
                                     title: session.displayName,
                                     subtitle: subtitle(for: session),
                                     isSelected: model.selection == session.id) {
                                model.selection = session.id
                            } trailing: {
                                StatusBadge(status: session.status)
                            }
                            .contextMenu {
                                Button("Mostrar en Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([session.folder])
                                }
                                Button("Eliminar", role: .destructive) { model.delete(session) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.bottom, Theme.panelPadding)
            }
        }
    }

    @ViewBuilder private var recordButton: some View {
        if model.recorder.isRecording {
            Button("Detener") { Task { await model.stopRecording() } }
                .buttonStyle(FilledButtonStyle(tint: Theme.recording))
                .fixedSize()
        } else {
            Button("Grabar") { Task { await model.startRecording() } }
                .buttonStyle(FilledButtonStyle())
                .fixedSize()
                .disabled(model.isBusy)
        }
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Sin grabaciones")
                .font(Theme.rowTitleFont)
                .foregroundStyle(Theme.textSecondary)
            Text("Graba desde la barra de menús, o arrastra aquí un archivo de audio o video.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.rowPadding)
        .padding(.vertical, Theme.Space.md)
    }

    /// subtitle is a recording's length and detected language, both of which
    /// come from the metadata sidecar and are absent on older sessions.
    private func subtitle(for session: Session) -> String? {
        guard let metadata = session.metadata else { return nil }
        var parts: [String] = []
        if metadata.durationSeconds > 0 { parts.append(formatDuration(metadata.durationSeconds)) }
        if let language = metadata.language, !language.isEmpty { parts.append(language) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let session = model.selectedSession {
            SessionDetailView(model: model, session: session)
        } else {
            VStack(spacing: Theme.Space.md) {
                Image(systemName: "doc.text")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textTertiary)
                Text("Ninguna grabación seleccionada")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in await model.importFile(url) }
        }
        return true
    }
}

/// MissingToolsView reports what is not installed and the command that installs
/// it, which is the CLI's error message turned into something clickable.
struct MissingToolsView: View {
    let tools: [Tool]
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Label(tool.binary, systemImage: tool.required ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(Theme.captionFont)
                        .foregroundStyle(tool.required ? Theme.warning : Theme.textSecondary)
                    Text(tool.installCommand)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Button("Volver a comprobar", action: onRecheck)
                .buttonStyle(.plain)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Space.md)
        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.warning.opacity(0.28), lineWidth: 1))
        .padding(.horizontal, Theme.Space.xs)
    }
}
