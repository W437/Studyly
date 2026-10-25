import Compression
import Foundation
import ImageIO
import SQLite3
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Cramless

/// Shared helpers for the capture, import, OCR and lecture tests: a private file store, an in-memory app, a ZIP
/// writer, an Anki collection builder, and text rendered into images and PDFs.
@MainActor
class CaptureTestCase: XCTestCase {
    var root: URL!
    private var previousLive: AppModel?

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appending(path: "capture-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileStore.rootOverride = root
        previousLive = AppModel.live
    }

    override func tearDown() async throws {
        FileStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        AppModel.live = previousLive
        try await super.tearDown()
    }

    /// An app on an in-memory store, with its own defaults and a frozen clock.
    func makeApp(now: Date = Date(timeIntervalSince1970: 1_790_000_000)) throws -> AppModel {
        let defaults = UserDefaults(suiteName: "capture-tests-\(UUID().uuidString)")!
        let app = AppModel(config: .resolve(), container: try Persistence.makeContainer(inMemory: true), defaults: defaults)
        app.clock = { now }
        return app
    }

    func makeCourse(_ app: AppModel, name: String = "Bio 101") -> Course {
        let course = Course(name: name, now: app.now)
        app.context.insert(course)
        app.save()
        return course
    }

    func temporaryFile(_ name: String, data: Data) throws -> URL {
        let url = root.appending(path: "incoming-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appending(path: name)
        try data.write(to: file)
        return file
    }
}

// MARK: - ZIP

/// Writes ZIP archives for the reader's tests: stored or deflated entries (raw DEFLATE via Compression).
enum ZipWriter {
    struct Entry {
        var name: String
        var data: Data
        var deflate: Bool
    }

    static func archive(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let payload = entry.deflate ? deflateRaw(entry.data) : entry.data
            let method: UInt16 = entry.deflate ? 8 : 0
            let offset = UInt32(out.count)
            let local: [Data] = [le32(0x0403_4b50), le16(20), le16(0x0800), le16(method), le16(0), le16(0x21), le32(crc),
                                 le32(UInt32(payload.count)), le32(UInt32(entry.data.count)), le16(UInt16(name.count)), le16(0),
                                 name, payload]
            for part in local { out.append(part) }
            let header: [Data] = [le32(0x0201_4b50), le16(20), le16(20), le16(0x0800), le16(method), le16(0), le16(0x21),
                                  le32(crc), le32(UInt32(payload.count)), le32(UInt32(entry.data.count)),
                                  le16(UInt16(name.count)), le16(0), le16(0), le16(0), le16(0), le32(0), le32(offset), name]
            for part in header { central.append(part) }
        }
        let directoryOffset = UInt32(out.count)
        out.append(central)
        let end: [Data] = [le32(0x0605_4b50), le16(0), le16(0), le16(UInt16(entries.count)), le16(UInt16(entries.count)),
                           le32(UInt32(central.count)), le32(directoryOffset), le16(0)]
        for part in end { out.append(part) }
        return out
    }

    static func deflateRaw(_ data: Data) -> Data {
        let capacity = data.count + 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let size = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            compression_encode_buffer(destination, capacity, raw.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return Data(bytes: destination, count: size)
    }

    static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}

// MARK: - Anki

/// Builds a schema-11 Anki collection with SQLite, the way Anki 2.1 exports it.
enum AnkiFixture {
    struct Note {
        var id: Int64
        var model: Int64
        var fields: [String]
    }

    struct Card {
        var id: Int64
        var note: Int64
        var deck: Int64 = 2001
        var ord: Int = 0
        var type: Int = 0
        var queue: Int = 0
        var due: Int64 = 0
        var ivl: Int = 0
        var factor: Int = 0
        var reps: Int = 0
        var lapses: Int = 0
        var odue: Int64 = 0
        var odid: Int64 = 0
        var data: String = ""
    }

    static let crt: Int64 = 1_700_000_000

    static let models = """
    {"1001": {"id": 1001, "name": "Basic", "type": 0, "sortf": 0,
              "flds": [{"name": "Front", "ord": 0}, {"name": "Back", "ord": 1}],
              "tmpls": [{"name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr id=answer>{{Back}}"}]},
     "1002": {"id": 1002, "name": "Cloze", "type": 1, "sortf": 0,
              "flds": [{"name": "Text", "ord": 0}, {"name": "Back Extra", "ord": 1}],
              "tmpls": [{"name": "Cloze", "ord": 0, "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}<br>{{Back Extra}}"}]},
     "1003": {"id": 1003, "name": "Basic (and reversed card)", "type": 0, "sortf": 0,
              "flds": [{"name": "Front", "ord": 0}, {"name": "Back", "ord": 1}],
              "tmpls": [{"name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr id=answer>{{Back}}"},
                        {"name": "Card 2", "ord": 1, "qfmt": "{{Back}}", "afmt": "{{FrontSide}}<hr id=answer>{{Front}}"}]}}
    """

    static let decks = """
    {"1": {"id": 1, "name": "Default"}, "2001": {"id": 2001, "name": "Biology::Unit 3::Mitosis"},
     "2002": {"id": 2002, "name": "Biology::Unit 3::Vocabulary"}}
    """

    /// Writes the collection file and returns its URL.
    static func collection(at url: URL, notes: [Note], cards: [Card], revlog: [(id: Int64, card: Int64)] = []) throws -> URL {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 1) }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null,
          ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null,
          models text not null, decks text not null, dconf text not null, tags text not null);
        CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null,
          usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null,
          flags integer not null, data text not null);
        CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null,
          mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null,
          ivl integer not null, factor integer not null, reps integer not null, lapses integer not null, left integer not null,
          odue integer not null, odid integer not null, flags integer not null, data text not null);
        CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null,
          ivl integer not null, lastIvl integer not null, factor integer not null, time integer not null, type integer not null);
        CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 2) }
        try run(db, "INSERT INTO col VALUES (1, ?, 0, 0, 11, 0, 0, 0, '{}', ?, ?, '{}', '{}')", [crt, models, decks])
        for note in notes {
            try run(db, "INSERT INTO notes VALUES (?, 'g', ?, 0, 0, '', ?, 0, 0, 0, '')",
                    [note.id, note.model, note.fields.joined(separator: "\u{1f}")])
        }
        for c in cards {
            try run(db, "INSERT INTO cards VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 0, ?)",
                    [c.id, c.note, c.deck, Int64(c.ord), Int64(c.type), Int64(c.queue), c.due, Int64(c.ivl), Int64(c.factor),
                     Int64(c.reps), Int64(c.lapses), c.odue, c.odid, c.data])
        }
        for entry in revlog {
            try run(db, "INSERT INTO revlog VALUES (?, ?, 0, 3, 1, 0, 2500, 5000, 1)", [entry.id, entry.card])
        }
        return url
    }

    private static func run(_ db: OpaquePointer?, _ sql: String, _ values: [Any]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 3) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let v as Int64: sqlite3_bind_int64(statement, position, v)
            case let v as String: sqlite3_bind_text(statement, position, v, -1, transient)
            default: sqlite3_bind_null(statement, position)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw NSError(domain: "sqlite", code: 4) }
    }

    /// Packs a collection file (and optional extra entries) into an .apkg.
    static func package(collection: URL, name: String = "collection.anki21", extra: [ZipWriter.Entry] = []) throws -> Data {
        let data = try Data(contentsOf: collection)
        return ZipWriter.archive([ZipWriter.Entry(name: name, data: data, deflate: true)] + extra
                                 + [ZipWriter.Entry(name: "media", data: Data("{\"0\": \"a.png\"}".utf8), deflate: false)])
    }
}

// MARK: - Rendering

enum Render {
    /// Lines of text drawn on a warm paper background, like a photographed handout.
    static func textImage(_ lines: [String], font: UIFont = .systemFont(ofSize: 40), size: CGSize = CGSize(width: 1200, height: 1000),
                          at origin: CGPoint = CGPoint(x: 60, y: 60)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var y = origin.y
            for line in lines {
                NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: UIColor(red: 0.08, green: 0.1, blue: 0.3, alpha: 1)])
                    .draw(at: CGPoint(x: origin.x, y: y))
                y += font.lineHeight * 1.6
            }
        }
    }

    static func jpeg(_ image: UIImage, orientation: CGImagePropertyOrientation = .up) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.cgImage!, [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A PDF whose pages are drawn by the closures (Letter size).
    static func pdf(pages: [(UIGraphicsPDFRendererContext) -> Void]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                page(context)
            }
        }
    }

    static func drawText(_ lines: [String], in context: UIGraphicsPDFRendererContext, size: CGFloat = 14, top: CGFloat = 72) {
        var y = top
        let font = UIFont.systemFont(ofSize: size)
        for line in lines {
            NSAttributedString(string: line, attributes: [.font: font]).draw(at: CGPoint(x: 72, y: y))
            y += font.lineHeight * 1.4
        }
    }
}
