import EventKit
import Foundation

/// What Cap's busy-day card reads of the calendar: when the person is taken, and nothing else. It runs on this iPhone, what it reads stays in memory, and nothing is sent anywhere.
protocol BusyCalendarReading: Sendable {
    var access: CalendarAccess { get }
    /// Asks iOS (it asks the person once, ever) and says what came of it.
    func requestAccess() async -> CalendarAccess
    func busyBlocks(from start: Date, to end: Date) async -> [BusyBlock]
}

/// The system's calendar. It needs full access to read at all, but looks only at an event's times and whether it's marked busy; it never touches a title, place, note or attendee.
struct LiveBusyCalendar: BusyCalendarReading {
    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notAsked
        case .fullAccess: .granted
        default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        _ = try? await EKEventStore().requestFullAccessToEvents()
        return access
    }

    func busyBlocks(from start: Date, to end: Date) async -> [BusyBlock] {
        guard access == .granted else { return [] }
        // A big calendar takes a while to read, and this is never worth a frame.
        return await Task.detached(priority: .utility) {
            let store = EKEventStore()
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).compactMap { event in
                guard Self.counts(availability: event.availability, allDay: event.isAllDay), let from = event.startDate, let until = event.endDate else { return nil }
                return BusyBlock(start: from, end: until)
            }
        }.value
    }

    /// Marked busy or away. A calendar that can't say (`notSupported`) counts for timed events only: a holiday or a birthday lasts all day and takes no one's time.
    static func counts(availability: EKEventAvailability, allDay: Bool) -> Bool {
        switch availability {
        case .busy, .unavailable: true
        case .notSupported: !allDay
        case .free, .tentative: false
        @unknown default: false
        }
    }
}

/// Reads nothing and asks for nothing: tests, and the harness unless it's asked to pretend.
struct NoBusyCalendar: BusyCalendarReading {
    var access: CalendarAccess { .denied }
    func requestAccess() async -> CalendarAccess { .denied }
    func busyBlocks(from start: Date, to end: Date) async -> [BusyBlock] { [] }
}

#if DEBUG
/// A calendar for the harness and the tests: an answer to the question, and the blocks it holds.
final class DemoBusyCalendar: BusyCalendarReading, @unchecked Sendable {
    private let lock = NSLock()
    private var state: CalendarAccess
    private var answer: CalendarAccess
    private let blocks: [BusyBlock]
    private var asked = 0

    init(access: CalendarAccess, answers: CalendarAccess = .granted, blocks: [BusyBlock] = []) {
        state = access
        answer = answers
        self.blocks = blocks
    }

    var access: CalendarAccess { lock.withLock { state } }
    var askedCount: Int { lock.withLock { asked } }

    func requestAccess() async -> CalendarAccess {
        lock.withLock {
            asked += 1
            state = answer
            return state
        }
    }

    func busyBlocks(from start: Date, to end: Date) async -> [BusyBlock] { heldBlocks }

    /// What it holds, if it may be read.
    var heldBlocks: [BusyBlock] { lock.withLock { state == .granted ? blocks : [] } }
}
#endif
