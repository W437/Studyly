import Foundation
import SwiftData

enum Persistence {
    static let models: [any PersistentModel.Type] = [
        Course.self, Source.self, SourcePage.self, Topic.self, StudyItem.self, ReviewLog.self, Exam.self,
        StudySession.self, DayRecord.self, Confusion.self, ChatThread.self, ChatMessage.self,
    ]

    static var schema: Schema { Schema(models) }

    /// The on-disk container for the app, or an in-memory one for tests, previews and the screenshot harness.
    /// The store lives in Application Support (the widget reads a snapshot file, never the store).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let url = FileStore.applicationSupport.appending(path: "Cramless.store")
            config = ModelConfiguration(schema: schema, url: url)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// Files the app keeps beside the store: page images, PDFs, lecture audio, imported decks.
/// Paths stored in models are relative to `root`, so a restored or moved container still resolves them.
enum FileStore {
    static var applicationSupport: URL {
        let url = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Overridden by tests so nothing writes into the real container.
    nonisolated(unsafe) static var rootOverride: URL?

    static var root: URL {
        let url = rootOverride ?? applicationSupport.appending(path: "Files", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    /// Writes data under `folder/name` and returns the relative path to store in a model.
    @discardableResult
    static func write(_ data: Data, folder: String, name: String) throws -> String {
        let dir = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let relative = "\(folder)/\(name)"
        try data.write(to: root.appending(path: relative), options: .atomic)
        return relative
    }

    /// Copies a file in (an imported PDF, a recording) and returns its relative path.
    @discardableResult
    static func copy(from source: URL, folder: String, name: String) throws -> String {
        let dir = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let relative = "\(folder)/\(name)"
        let target = root.appending(path: relative)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: source, to: target)
        return relative
    }

    static func removeFolder(_ folder: String) {
        try? FileManager.default.removeItem(at: root.appending(path: folder, directoryHint: .isDirectory))
    }
}

extension Calendar {
    /// Whole local days from `a` to `b` (negative when `b` is earlier). Counts calendar days, so a 23- or
    /// 25-hour day (a daylight-saving change, a day that starts at 01:00) still counts as one. Use this for every
    /// day count in the app; never divide seconds by 86 400.
    func dayDistance(from a: Date, to b: Date) -> Int {
        // Read back in this calendar's own system on a UTC clock (Engine/DayMath.swift), so Buddhist or Hebrew
        // calendars count across month ends and leap days correctly too.
        dayNumber(for: b) - dayNumber(for: a)
    }

    /// "yyyy-MM-dd" for the local day containing `date`.
    func dayKey(for date: Date) -> String {
        let c = dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// A UTC Gregorian calendar, for day arithmetic that must not see time zones.
    static let gregorianUTC: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
