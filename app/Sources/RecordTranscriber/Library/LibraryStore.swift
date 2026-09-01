import Foundation
import Observation

/// LibraryStore lists the recordings in the library folder and creates new ones.
///
/// It holds no state the folder does not: `reload` rebuilds the list from disk,
/// which is what keeps the app correct when the user rearranges things behind
/// its back.
@Observable
final class LibraryStore {
    private(set) var sessions: [Session] = []

    var folder: URL {
        didSet { reload() }
    }

    init(folder: URL) {
        self.folder = folder
        reload()
    }

    /// reload rebuilds the session list, newest first. A missing library folder
    /// is an empty library, not an error: the folder is created on first use.
    func reload() {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles])

        sessions = (contents ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(Session.init(folder:))
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// createSession makes the folder for a recording about to start. Two
    /// recordings begun in the same minute would otherwise collide, so a
    /// counter is appended until the name is free.
    @discardableResult
    func createSession(startedAt: Date = Date()) throws -> Session {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let base = Session.folderName(for: startedAt)
        var candidate = folder.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(suffix)")
            suffix += 1
        }

        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        let session = Session(folder: candidate)
        sessions.insert(session, at: 0)
        return session
    }

    /// delete removes a session's folder and everything in it.
    func delete(_ session: Session) throws {
        try FileManager.default.removeItem(at: session.folder)
        sessions.removeAll { $0.id == session.id }
    }
}
