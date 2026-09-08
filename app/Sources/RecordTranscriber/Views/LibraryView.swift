import SwiftUI
import UniformTypeIdentifiers

enum LibraryWindow {
    static let id = "library"
}

/// LibraryView is the window: the recordings or the imported files on the
/// left, whatever the selected one produced on the right.
struct LibraryView: View {
    @Bindable var model: AppModel

    /// renaming is the session whose new name is being typed, and newName the
    /// text. They live here rather than in the row or the detail view because
    /// both open the same field.
    @State private var renaming: Session?
    @State private var newName = ""

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
        .onDrop(of: [.audio, .movie], isTargeted: nil, perform: handleDrop)
        .alert("No se pudo completar", isPresented: showingFailure) {
            Button("Entendido", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
        .alert("Renombrar", isPresented: showingRename, presenting: renaming) { session in
            TextField("Nombre", text: $newName)
            Button("Renombrar") { model.rename(session, to: newName) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("El nombre es el de la carpeta en la biblioteca.")
        }
        .task { model.recheckTools() }
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }

    private var showingRename: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func startRenaming(_ session: Session) {
        newName = session.name
        renaming = session
    }

    // MARK: Sidebar

    private var sessions: [Session] {
        model.librarySection == .recordings ? model.library.sessions : model.imports.sessions
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                TabStrip(items: AppModel.LibrarySection.allCases,
                         title: \.title,
                         selection: $model.librarySection)
                sectionAction
                if let progress = model.importProgress {
                    importStatus(progress)
                }
            }
            .padding(.horizontal, Theme.panelPadding)
            .padding(.vertical, Theme.Space.md)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !model.missingTools.filter(\.required).isEmpty {
                        MissingToolsView(tools: model.missingTools) { model.recheckTools() }
                            .padding(.bottom, Theme.Space.md)
                    }

                    if sessions.isEmpty {
                        emptyList
                    } else {
                        ForEach(sessions) { session in
                            PanelRow(icon: "waveform",
                                     title: session.displayName,
                                     subtitle: subtitle(for: session),
                                     isSelected: model.selection == session.id) {
                                model.selection = session.id
                            } trailing: {
                                StatusBadge(status: session.status)
                            }
                            .contextMenu {
                                Button("Renombrar…") { startRenaming(session) }
                                    .disabled(model.isBusy)
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

    @ViewBuilder private var sectionAction: some View {
        switch model.librarySection {
        case .recordings:
            recordButton
        case .imports:
            Button("Transcribir archivo…") { importFromDialog() }
                .buttonStyle(FilledButtonStyle())
                .disabled(model.isBusy)
        }
    }

    @ViewBuilder private var recordButton: some View {
        if model.recorder.isRecording {
            Button("Detener") { Task { await model.stopRecording() } }
                .buttonStyle(FilledButtonStyle(tint: Theme.recording))
        } else {
            Button("Grabar") { Task { await model.startRecording() } }
                .buttonStyle(FilledButtonStyle())
                .disabled(model.isBusy)
        }
    }

    private func importStatus(_ progress: AppModel.ImportProgress) -> some View {
        HStack {
            Text("Transcribiendo archivo \(min(progress.done + 1, progress.total)) de \(progress.total)")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Cancelar") { model.cancelImports() }
                .buttonStyle(.plain)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.accent)
        }
    }

    private var emptyList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(model.librarySection == .recordings ? "Sin grabaciones" : "Sin archivos")
                .font(Theme.rowTitleFont)
                .foregroundStyle(Theme.textSecondary)
            Text(model.librarySection == .recordings
                ? "Graba desde la barra de menús, o arrastra aquí un archivo de audio o video."
                : "Elige Transcribir archivo…, o arrastra aquí audio o video.")
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
            SessionDetailView(model: model, session: session, onRename: startRenaming)
                // Keyed by session so the tab state starts over per session
                // rather than carrying over from the one shown before.
                .id(session.id)
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

    // MARK: Importing

    private func importFromDialog() {
        let urls = MediaFilePicker.chooseFiles()
        guard !urls.isEmpty else { return }
        Task { await model.importFiles(urls) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadURL(from: provider) { urls.append(url) }
            }
            await model.importFiles(urls)
        }
        return true
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
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
