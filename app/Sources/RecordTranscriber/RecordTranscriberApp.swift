import SwiftUI

@main
struct RecordTranscriberApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            // The icon carries the state, so a recording that is still running
            // is visible without opening anything.
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Grabaciones", id: LibraryWindow.id) {
            LibraryView(model: model)
                .frame(minWidth: 720, minHeight: 440)
        }

        Settings {
            PreferencesView(model: model)
        }
    }

    private var menuBarSymbol: String {
        if model.recorder.isRecording { return "record.circle.fill" }
        if model.runner.isRunning { return "waveform.badge.gearshape" }
        return "waveform"
    }
}
