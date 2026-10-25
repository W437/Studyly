import Foundation
import XCTest
@testable import Cramless

/// Helpers for the Widgets lane's tests: a fixed clock and calendar, and an in-memory app model.
enum WidgetTestSupport {
    /// New York, so daylight saving (Nov 1, 2026) shows up in day arithmetic.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    /// Thursday, Oct 22, 2026, 09:00 in New York.
    static let now = date(2026, 10, 22, 9, 0)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// An in-memory app with side effects off (unit tests), onboarding done, the clock and calendar fixed. The
    /// caller keeps it alive (`AppModel.live` is weak) and restores `AppModel.live` afterwards if it cares.
    @MainActor
    static func makeApp(seed: Bool = false, now: Date = WidgetTestSupport.now) -> AppModel {
        let defaults = UserDefaults(suiteName: "capling.widget-tests.\(UUID().uuidString)")!
        let config = AppConfig.resolve(environment: ["XCTestConfigurationFilePath": "widget-tests"], info: [:])
        let app = AppModel(config: config, defaults: defaults)
        app.clock = { now }
        app.calendar = calendar
        app.settings.onboardingCompleted = true
        if seed { SampleData.seed(into: app) }
        return app
    }

    /// A course and an exam `days` days from `now` at 9:00.
    @MainActor
    @discardableResult
    static func addExam(to app: AppModel, title: String, course: String, color: CourseColor = .sky, days: Int,
                        hour: Int = 9) -> Exam {
        let c = Course(name: course, color: color, now: app.now)
        app.context.insert(c)
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: app.now))!
        let exam = Exam(course: c, title: title, date: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!,
                        now: app.now)
        app.context.insert(exam)
        c.exams.append(exam)
        try? app.context.save()
        return exam
    }

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-tests-\(UUID().uuidString)",
                                                                  directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
