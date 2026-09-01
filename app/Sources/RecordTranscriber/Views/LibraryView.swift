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
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar { toolbar }
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

    @ViewBuilder private var sidebar: some View {
        List(selection: $model.selection) {
            if !model.missingTools.filter(\.required).isEmpty {
                Section("Dependencias") {
                    MissingToolsView(tools: model.missingTools) { model.recheckTools() }
                }
            }
            Section("Grabaciones") {
                ForEach(model.library.sessions) { session in
                    SessionRow(session: session).tag(session.id)
                        .contextMenu {
                            Button("Mostrar en Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([session.folder])
                            }
                            Button("Eliminar", role: .destructive) { model.delete(session) }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .overlay {
            if model.library.sessions.isEmpty && model.missingTools.filter(\.required).isEmpty {
                ContentUnavailableView(
                    "Sin grabaciones",
                    systemImage: "waveform",
                    description: Text("Graba desde la barra de menús, o arrastra un archivo de audio o video aquí."))
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let session = model.selectedSession {
            SessionDetailView(model: model, session: session)
        } else {
            ContentUnavailableView("Ninguna grabación seleccionada", systemImage: "doc.text")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.recorder.isRecording {
                Button {
                    Task { await model.stopRecording() }
                } label: {
                    Label("Detener", systemImage: "stop.fill")
                }
            } else {
                Button {
                    Task { await model.startRecording() }
                } label: {
                    Label("Grabar", systemImage: "record.circle")
                }
                .disabled(model.isBusy)
            }
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

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.name).font(.body)
            HStack(spacing: 6) {
                if session.hasAudio { Label("audio", systemImage: "waveform") }
                if session.transcriptText != nil { Label("texto", systemImage: "doc.text") }
                if session.hasSummary { Label("resumen", systemImage: "list.bullet.rectangle") }
            }
            .font(.caption2)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// MissingToolsView reports what is not installed and the command that installs
/// it, which is the CLI's error message turned into something clickable.
struct MissingToolsView: View {
    let tools: [Tool]
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: 2) {
                    Label(tool.binary, systemImage: tool.required ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(tool.required ? .orange : .secondary)
                    Text(tool.installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Volver a comprobar", action: onRecheck)
                .buttonStyle(.link)
        }
        .padding(.vertical, 4)
    }
}
