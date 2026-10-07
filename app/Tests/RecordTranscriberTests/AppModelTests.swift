import Foundation
import Testing
@testable import RecordTranscriber

@MainActor private func isolatedModel() -> AppModel {
    let defaults = UserDefaults(suiteName: "record-transcriber-tests-\(UUID().uuidString)")!
    return AppModel(preferences: Preferences(defaults: defaults))
}

@Test @MainActor func reportsAFailedMetadataSave() {
    let model = isolatedModel()
    let missingFolder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")

    model.save(SessionMetadata(durationSeconds: 12), to: missingFolder)

    #expect(model.failure?.hasPrefix("No se pudieron guardar los datos de la sesión") == true)
}

@Test @MainActor func keepsQuietWhenTheMetadataSaves() throws {
    let model = isolatedModel()
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    model.save(SessionMetadata(durationSeconds: 12), to: folder)

    #expect(model.failure == nil)
    #expect(SessionMetadata.load(from: folder)?.durationSeconds == 12)
}
