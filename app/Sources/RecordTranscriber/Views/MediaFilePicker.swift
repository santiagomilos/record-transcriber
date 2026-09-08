import AppKit
import UniformTypeIdentifiers

/// MediaFilePicker is the one open dialog for files to transcribe, shared by
/// the panel row and the window button.
///
/// It is an `NSOpenPanel` rather than SwiftUI's `.fileImporter` because the
/// latter belongs to the view that presents it, and the menu bar popover closes
/// the moment the dialog takes key: the panel would need its own copy of the
/// presentation state, and opening the window afterwards would be split across
/// two call sites. A modal panel returns the chosen files to whoever asked.
enum MediaFilePicker {
    @MainActor
    static func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = "Transcribir"
        panel.message = "Elige los archivos de audio o video que quieres transcribir."
        // An accessory app is never activated on its own, and a modal panel
        // opened by an inactive app appears behind whatever is in front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
