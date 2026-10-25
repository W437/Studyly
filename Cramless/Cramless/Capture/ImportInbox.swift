import Foundation

/// A file "Open in Capling" (or the share sheet) handed over, kept until the import sheet or the capture flow
/// takes it: `imports/pending/<name>` under the file store. One at a time; a new file replaces the old one.
/// iOS delivers such files as copies in `Documents/Inbox`, which is emptied once the file is kept here.
enum ImportInbox {
    static let folder = "imports/pending"

    /// Keeps a copy of the file and returns its URL.
    @discardableResult
    static func keep(_ url: URL) throws -> URL {
        clear()
        let name = url.lastPathComponent.isEmpty ? "import" : url.lastPathComponent
        let relative = try withFileAccess(url) { try FileStore.copy(from: url, folder: folder, name: name) }
        // Only the app's own inbox copy is removed; a file picked in Files stays where the person keeps it.
        let appInbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory).standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(appInbox + "/") { try? FileManager.default.removeItem(at: url) }
        return FileStore.url(for: relative)
    }

    /// The file waiting for the import sheet, if any.
    static var pending: URL? {
        let directory = FileStore.url(for: folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { !$0.lastPathComponent.hasPrefix(".") }
    }

    static func clear() {
        FileStore.removeFolder(folder)
    }

    /// Deletes `url` when it is the waiting file (it has been copied into a source).
    static func release(_ url: URL) {
        let directory = FileStore.url(for: folder).standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(directory) { try? FileManager.default.removeItem(at: url) }
    }
}

extension DeckImporter {
    /// Whether text read from a file is a deck rather than notes: a CSV header with front and back columns, or a
    /// Quizlet export split by tabs or " - " on nearly every line. Commas alone don't count (prose is full of them).
    static func looksLikeDeck(_ text: String) -> Bool {
        if CSVImporter.hasKnownHeader(text) { return true }
        let lines = TextPaginator.normalized(text).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return false }
        for separator in ["\t", " - "] {
            let hits = lines.filter { $0.contains(separator) }.count
            if Double(hits) >= 0.8 * Double(lines.count) { return true }
        }
        return false
    }
}
