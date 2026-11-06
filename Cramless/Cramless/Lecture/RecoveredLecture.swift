import Foundation

/// A lecture that was recording when the app was closed (a crash, a force-quit) and that launch kept
/// (`AppModel.recoverInterruptedLectures`): its audio up to the cut, and whatever was transcribed by then.
struct RecoveredLecture: Equatable, Sendable {
    var id: UUID
    /// Seconds of audio kept.
    var duration: Double

    /// Shorter than this is a stray tap on record, not worth a word.
    static let worthTelling: Double = 10

    /// The toast that says so: "Cap kept your lecture up to 41:20." with Open (its notes), or for several, "Cap kept 2 lectures that
    /// were cut off." (no button: they're in the Library). Nil when there is nothing worth telling.
    @MainActor static func toast(for lectures: [RecoveredLecture]) -> (message: LocalizedStringResource, action: ToastAction?)? {
        let kept = lectures.filter { $0.duration >= worthTelling }
        switch kept.count {
        case 0:
            return nil
        case 1:
            let lecture = kept[0]
            return ("Cap kept your lecture up to \(LectureSession.clock(lecture.duration)).",
                    .push(.lectureNotes(lecture.id), .library))
        default:
            return ("Cap kept \(kept.count) lectures that were cut off.", nil)
        }
    }
}
