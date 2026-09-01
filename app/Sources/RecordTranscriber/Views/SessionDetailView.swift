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

    @State private var tab: Tab = .transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.runner.isRunning {
                ProgressView(value: model.runner.phase.fraction) {
                    Text(model.runner.phase.label)
                }
                .progressViewStyle(.linear)
                .padding()
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            content
        }
        .navigationTitle(session.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.transcribe(session) }
                } label: {
                    Label("Transcribir de nuevo", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy || !session.hasAudio)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([session.folder])
                } label: {
                    Label("Mostrar en Finder", systemImage: "folder")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        let text = tab == .transcript ? session.transcriptText : session.summaryText
        if let text, !text.isEmpty {
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else if model.runner.isRunning {
            ContentUnavailableView("Procesando", systemImage: "hourglass")
        } else {
            ContentUnavailableView(
                tab == .transcript ? "Sin transcripción" : "Sin resumen",
                systemImage: "doc",
                description: Text(session.hasAudio
                    ? "Usa \"Transcribir de nuevo\" para generarla."
                    : "Esta grabación no tiene audio."))
        }
    }
}
