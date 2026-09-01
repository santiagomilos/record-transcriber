import SwiftUI

struct PreferencesView: View {
    let model: AppModel
    /// The preferences object is bound directly: a binding cannot be formed
    /// through AppModel's `let preferences`.
    @Bindable var preferences: Preferences
    @State private var choosingFolder = false

    init(model: AppModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        Form {
            Section("Biblioteca") {
                LabeledContent("Carpeta") {
                    HStack {
                        Text(preferences.libraryFolder.path)
                            .truncationMode(.head)
                            .lineLimit(1)
                        Button("Cambiar…") { choosingFolder = true }
                    }
                }
            }

            Section("Transcripción") {
                Picker("Idioma", selection: $preferences.language) {
                    Text("Detectar").tag("auto")
                    Text("Español").tag("es")
                    Text("Inglés").tag("en")
                }
                Picker("Resumen", selection: $preferences.summaryKind) {
                    Text("Ninguno").tag("none")
                    Text("Resumen").tag("resumen")
                    Text("Minuta").tag("minuta")
                }
                LabeledContent("Formatos") {
                    HStack {
                        ForEach(Preferences.availableFormats, id: \.self) { format in
                            Toggle(format, isOn: binding(for: format))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
                TextField("Modelo", text: $preferences.model)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                preferences.libraryFolder = url
                model.library.folder = url
            }
        }
    }

    /// binding keeps at least one format selected: the CLI rejects an empty
    /// format list, and a preferences pane should not be able to produce a
    /// configuration that fails at run time.
    private func binding(for format: String) -> Binding<Bool> {
        Binding(
            get: { preferences.formats.contains(format) },
            set: { isOn in
                var formats = preferences.formats
                if isOn {
                    if !formats.contains(format) { formats.append(format) }
                } else if formats.count > 1 {
                    formats.removeAll { $0 == format }
                }
                preferences.formats = Preferences.availableFormats.filter { formats.contains($0) }
            })
    }
}
