import Foundation

/// A problem read off a photo, on this iPhone (`TextRecognizer`, math too in this version): the words the student checks before they go to
/// Cap. The image is staged only for as long as the reading takes and deleted either way, so nothing of the photo outlives this call and
/// nothing of it is ever sent.
enum SnapReader {
    struct Reading: Equatable, Sendable {
        var text: String
        var issue: PageRead.Issue?

        /// There are words to check. No text and an unsure read keep no words at all (the gate in `TextRecognizer`): try again, or type it.
        var hasWords: Bool { !text.isEmpty }
    }

    /// More than any one problem: a whole page read by mistake is the student's to cut, and the chat's message limit is far above it.
    static let maxCharacters = 4_000

    static func read(stagedAt path: String, preferredLanguages: [String] = Locale.preferredLanguages) async -> Reading {
        defer { PageImageStore.discardStaged([path]) }
        guard var page = try? await TextRecognizer.read(imageAt: path, pageIndex: 0, preferredLanguages: preferredLanguages) else {
            return Reading(text: "", issue: .unreadable)
        }
        // A sheet in English on an iPhone set to another language: read with that language first, printed English scores under the gate. The
        // student checks the words before they go anywhere, so a second look costs half a second and risks nothing.
        if page.lines.isEmpty, preferredLanguages.first?.hasPrefix("en") != true,
           let english = try? await TextRecognizer.read(imageAt: path, pageIndex: 0, preferredLanguages: ["en-US"]), !english.lines.isEmpty {
            page = english
        }
        return reading(from: page)
    }

    /// The words of a read page, line by line in reading order.
    static func reading(from page: CapturedPage) -> Reading {
        Reading(text: String(page.text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines), issue: page.read.issue)
    }
}
