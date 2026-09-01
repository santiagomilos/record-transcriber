import SwiftUI

@main
struct RecordTranscriberApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Grabaciones", id: LibraryWindow.id) {
            LibraryView(model: model)
                .frame(minWidth: 760, minHeight: 460)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// MenuBarLabel is what the status item shows. The icon carries the state, so a
/// recording that is still running is visible without opening anything — and
/// while it runs the elapsed time is spelled out beside it, which is the one
/// thing worth reading at a glance.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.recorder.isRecording {
            Label {
                Text(formatDuration(model.recorder.elapsed))
            } icon: {
                Image(systemName: "record.circle.fill")
                    .symbolEffect(.pulse, options: .repeating)
            }
        } else if model.runner.isRunning {
            Image(systemName: "waveform.badge.gearshape")
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            Image(systemName: "waveform")
        }
    }
}
