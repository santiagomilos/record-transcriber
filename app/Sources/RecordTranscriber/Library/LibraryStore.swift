import Foundation
import Observation

/// LibraryStore lists the sessions in one folder and creates new ones.
///
/// It holds no state the folder does not: `reload` rebuilds the list from disk,
/// which is what keeps the app correct when the user rearranges things behind
/// its back.
///
/// The app keeps two: the recordings it made, in the library folder itself, and
/// the files imported from elsewhere, in a subfolder of it. The recordings store
/// is told to skip that subfolder, or it would list it as a recording.
@Observable
final class LibraryStore {
    /// importsFolderName is where imported files live inside the library folder.
    static let importsFolderName = "Archivos"

    static func importsFolder(in library: URL) -> URL {
        library.appendingPathComponent(importsFolderName)
    }

    private(set) var sessions: [Session] = []

    var folder: URL {
        didSet { reload() }
    }

    /// excludedFolderNames are subfolders that are not sessions.
    private let excludedFolderNames: Set<String>

    init(folder: URL, excludedFolderNames: Set<String> = []) {
        self.folder = folder
        self.excludedFolderNames = excludedFolderNames
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
            .filter { !excludedFolderNames.contains($0.lastPathComponent) }
            .map(Session.init(folder:))
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// createSession makes the folder for a recording about to start.
    @discardableResult
    func createSession(startedAt: Date = Date()) throws -> Session {
        try createSession(named: Session.folderName(for: startedAt))
    }

    /// createSession makes a session folder with the given name. Two sessions
    /// wanting the same name would otherwise collide, so a counter is appended
    /// until the name is free.
    @discardableResult
    func createSession(named name: String) throws -> Session {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let candidate = freeFolder(named: name)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        let session = Session(folder: candidate)
        sessions.insert(session, at: 0)
        return session
    }

    /// rename moves a session's folder to a new name and returns the session as
    /// it is now listed. The name is trimmed; a collision gets the same counter
    /// a new session would. Renaming to the current name changes nothing.
    func rename(_ session: Session, to name: String) throws -> Session {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("."),
              !trimmed.contains("/"),
              !trimmed.contains(":"),
              // A recording renamed to the imports folder's name would vanish
              // from the list on the next reload.
              !excludedFolderNames.contains(trimmed)
        else { throw LibraryError.invalidName }
        if trimmed == session.name { return session }

        let destination = freeFolder(named: trimmed)
        try FileManager.default.moveItem(at: session.folder, to: destination)
        reload()
        return Session(folder: destination)
    }

    /// delete removes a session's folder and everything in it.
    func delete(_ session: Session) throws {
        try FileManager.default.removeItem(at: session.folder)
        sessions.removeAll { $0.id == session.id }
    }

    /// freeFolder is the first of `name`, `name 2`, `name 3`... that does not
    /// exist yet inside the library folder.
    private func freeFolder(named name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(suffix)")
            suffix += 1
        }
        return candidate
    }
}

/// LibraryError is what the library refuses to do, worded for the alert that
/// shows it.
enum LibraryError: LocalizedError {
    case invalidName

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "El nombre no puede estar vacío ni contener \"/\" o \":\"."
        }
    }
}
