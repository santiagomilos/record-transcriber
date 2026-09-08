import SwiftUI

/// PreferencesView is the panel's second screen, reached from the header gear
/// and left through its own back link, the way the reference does it.
struct PreferencesView: View {
    let model: AppModel
    /// The preferences object is bound directly: a binding cannot be formed
    /// through AppModel's `let preferences`.
    @Bindable var preferences: Preferences
    let onBack: () -> Void

    @State private var choosingFolder = false

    init(model: AppModel, onBack: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            library
            transcription
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                model.setLibraryFolder(url)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            BackLink(title: "Panel", action: onBack)
            Text("Preferencias")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.xs)
        }
        .padding(.bottom, Theme.Space.xs)
    }

    // MARK: Sections

    /// The library folder gets a row of its own rather than a label-and-control
    /// line: a path is too long to sit beside its own label at this width, and
    /// truncating it hides the end that says which folder it is.
    private var library: some View {
        section("Biblioteca") {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Carpeta")
                    .font(Theme.rowTitleFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(preferences.libraryFolder.path)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .truncationMode(.head)
                    .lineLimit(1)
                Button("Cambiar carpeta…") { choosingFolder = true }
                    .buttonStyle(FilledButtonStyle(tint: Theme.textPrimary, isProminent: false))
            }
            .padding(.vertical, Theme.Space.xs)

            SettingRow(label: "Archivos") {
                Picker("", selection: $preferences.importNaming) {
                    Text("Nombre original").tag(Preferences.ImportNaming.fileName)
                    Text("Fecha").tag(Preferences.ImportNaming.date)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var transcription: some View {
        section("Transcripción") {
            SettingRow(label: "Idioma") {
                Picker("", selection: $preferences.language) {
                    Text("Detectar").tag("auto")
                    Text("Español").tag("es")
                    Text("Inglés").tag("en")
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingRow(label: "Resumen") {
                Picker("", selection: $preferences.summaryKind) {
                    ForEach(Preferences.summaryKinds, id: \.self) { kind in
                        Text(Preferences.summaryKindName(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingRow(label: "Formatos") {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(Preferences.availableFormats, id: \.self) { format in
                        FormatChip(format: format,
                                   isOn: preferences.formats.contains(format)) {
                            toggle(format)
                        }
                    }
                }
            }

            SettingRow(label: "Modelo") {
                TextField("", text: $preferences.model)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.rowRadius)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1))
            }
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionLabel(text: title)
                .padding(.horizontal, Theme.Space.xs)
            PanelCard(padding: Theme.Space.md) {
                content()
            }
        }
    }

    /// toggle keeps at least one format selected: the CLI rejects an empty
    /// format list, and a preferences pane should not be able to produce a
    /// configuration that fails at run time.
    private func toggle(_ format: String) {
        var formats = preferences.formats
        if formats.contains(format) {
            guard formats.count > 1 else { return }
            formats.removeAll { $0 == format }
        } else {
            formats.append(format)
        }
        preferences.formats = Preferences.availableFormats.filter { formats.contains($0) }
    }
}

/// SettingRow is one preference: its name on the left, its control on the right.
private struct SettingRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            Text(label)
                .font(Theme.rowTitleFont)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 72, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

/// FormatChip is one output format, on or off. Chips rather than checkboxes
/// because the three formats are one choice read together.
private struct FormatChip: View {
    let format: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(format)
                .font(Theme.captionFont)
                .foregroundStyle(isOn ? .white : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 4)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.cardBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isOn { return Theme.accent }
        return isHovering ? Theme.rowHover : .clear
    }
}
