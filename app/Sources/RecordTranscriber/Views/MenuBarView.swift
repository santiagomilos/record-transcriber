import SwiftUI

/// MenuBarView is the control that is reachable while another app is in the
/// foreground, which is where recording actually starts and stops.
struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The window carries the same message in an alert, but it is often
            // closed while recording, and a failure nobody sees is a failure
            // that looks like nothing happening at all.
            if let failure = model.failure {
                VStack(alignment: .leading, spacing: 4) {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Descartar") { model.failure = nil }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Divider()
            }

            header

            if model.recorder.isRecording {
                LevelMeter(levels: model.recorder.levels)
            }

            if model.runner.isRunning {
                ProgressView(value: model.runner.phase.fraction) {
                    Text(model.runner.phase.label).font(.caption)
                }
                .progressViewStyle(.linear)
            }

            if !model.missingTools.filter(\.required).isEmpty {
                Text("Faltan dependencias — abre la ventana para verlas")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            Button("Abrir grabaciones") { openWindow(id: LibraryWindow.id) }
                .keyboardShortcut("o")
            Button("Salir") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder private var header: some View {
        if model.recorder.isRecording {
            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Detener  \(formatDuration(model.recorder.elapsed))", systemImage: "stop.fill")
            }
            .keyboardShortcut("r")

            Button("Descartar grabación", role: .destructive) { model.cancelRecording() }
                .font(.caption)
        } else {
            Button {
                Task { await model.startRecording() }
            } label: {
                Label("Grabar", systemImage: "record.circle")
            }
            .keyboardShortcut("r")
            .disabled(model.isBusy)
        }
    }
}

/// LevelMeter shows both sources separately. Two bars rather than one is
/// deliberate: the common failure is capturing only your own voice, and a single
/// mixed bar hides it.
struct LevelMeter: View {
    let levels: AudioCapture.Levels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar(label: "Micrófono", level: levels.microphone)
            bar(label: "Sistema", level: levels.system)
        }
    }

    private func bar(label: String, level: Float) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(level > 0.001 ? Color.accentColor : Color.secondary)
                        .frame(width: geometry.size.width * CGFloat(displayLevel(level)))
                }
            }
            .frame(height: 6)
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
