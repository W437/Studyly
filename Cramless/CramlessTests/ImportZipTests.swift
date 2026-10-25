import XCTest
@testable import Cramless

/// The minimal ZIP reader against archives written in the test: stored and deflated entries, CRC checks, damage.
@MainActor
final class ImportZipTests: CaptureTestCase {
    private let text = Data(String(repeating: "Mitosis makes two identical daughter cells. ", count: 400).utf8)
    private let binary = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 7919 &+ 13) })

    func testReadsStoredAndDeflatedEntries() throws {
        let data = ZipWriter.archive([
            .init(name: "stored.txt", data: text, deflate: false),
            .init(name: "deflated.txt", data: text, deflate: true),
            .init(name: "folder/binary.bin", data: binary, deflate: true),
            .init(name: "empty", data: Data(), deflate: false),
        ])
        let archive = try ZipArchive(data: data)
        XCTAssertEqual(archive.names, ["stored.txt", "deflated.txt", "folder/binary.bin", "empty"])
        let deflated = try XCTUnwrap(archive.entry(named: "deflated.txt"))
        XCTAssertEqual(deflated.method, 8)
        XCTAssertLessThan(deflated.compressedSize, deflated.size, "the deflated entry is actually compressed")
        XCTAssertEqual(try archive.contents(of: XCTUnwrap(archive.entry(named: "stored.txt"))), text)
        XCTAssertEqual(try archive.contents(of: deflated), text)
        XCTAssertEqual(try archive.contents(of: XCTUnwrap(archive.entry(named: "folder/binary.bin"))), binary)
        XCTAssertEqual(try archive.contents(of: XCTUnwrap(archive.entry(named: "empty"))), Data())
    }

    func testExtractsToAFileInChunks() throws {
        let big = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: ($0 / 7) &* 31) })
        let archive = try ZipArchive(data: ZipWriter.archive([.init(name: "big.bin", data: big, deflate: true)]))
        let target = root.appending(path: "big.bin")
        try archive.extract(XCTUnwrap(archive.entry(named: "big.bin")), to: target)
        XCTAssertEqual(try Data(contentsOf: target), big)
    }

    func testReadsAnArchiveOpenedFromDisk() throws {
        let url = try temporaryFile("deck.apkg", data: ZipWriter.archive([.init(name: "a.txt", data: text, deflate: true)]))
        let archive = try ZipArchive(url: url)
        XCTAssertEqual(try archive.contents(of: XCTUnwrap(archive.entry(named: "a.txt"))), text)
    }

    func testCorruptDataFailsTheChecksum() throws {
        var data = ZipWriter.archive([.init(name: "stored.txt", data: text, deflate: false)])
        // Flip a byte inside the stored payload (after the 30-byte header and the 10-byte name).
        data[30 + 10 + 100] ^= 0xFF
        let archive = try ZipArchive(data: data)
        XCTAssertThrowsError(try archive.contents(of: XCTUnwrap(archive.entry(named: "stored.txt")))) { error in
            XCTAssertEqual(error as? CaptureError, .damagedArchive)
        }
    }

    func testTruncatedDeflateFails() throws {
        let full = ZipWriter.archive([.init(name: "d.txt", data: text, deflate: true)])
        let archive = try ZipArchive(data: full)
        var entry = try XCTUnwrap(archive.entry(named: "d.txt"))
        entry.compressedSize /= 2
        XCTAssertThrowsError(try archive.contents(of: entry))
    }

    func testNotAZipIsDamaged() {
        XCTAssertThrowsError(try ZipArchive(data: Data("just some text, not an archive".utf8))) { error in
            XCTAssertEqual(error as? CaptureError, .damagedArchive)
        }
        XCTAssertThrowsError(try ZipArchive(data: Data()))
    }

    func testCRC32MatchesTheKnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }
}
