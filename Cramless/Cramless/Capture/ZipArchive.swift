import Compression
import Foundation

/// Just enough ZIP to open an Anki package (no dependency): the central directory, stored and deflated entries
/// (raw DEFLATE through the Compression framework's `COMPRESSION_ZLIB`), ZIP64 sizes and offsets, and a CRC-32
/// check on everything extracted. Encrypted entries and other methods (zstd, bzip2, LZMA) are refused by name.
struct ZipArchive {
    struct Entry: Hashable, Sendable {
        var name: String
        var method: UInt16
        var flags: UInt16
        var crc32: UInt32
        var compressedSize: UInt64
        var size: UInt64
        var localHeaderOffset: UInt64

        var isDirectory: Bool { name.hasSuffix("/") }
    }

    /// Entries larger than this are refused rather than inflated (a zip bomb, or a deck no phone should import).
    static let maxEntrySize: UInt64 = 2 << 30

    let data: Data
    let entries: [Entry]

    /// Memory-maps the file, so a large deck isn't read into memory up front.
    init(url: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: url, options: .alwaysMapped) } catch { throw CaptureError.damagedArchive }
        try self.init(data: data)
    }

    init(data: Data) throws {
        // Offsets below are from the first byte; a slice of a larger Data is copied so they hold.
        let data = data.startIndex == 0 ? data : Data(data)
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    var names: [String] { entries.map(\.name) }

    /// An entry's contents in memory (for small entries: a media map, a CSV).
    func contents(of entry: Entry) throws -> Data {
        var output = Data()
        output.reserveCapacity(Int(min(entry.size, 64 << 20)))
        try inflate(entry) { output.append($0) }
        return output
    }

    /// Writes an entry to a file, a chunk at a time (an Anki collection can be hundreds of megabytes).
    func extract(_ entry: Entry, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { throw CaptureError.damagedArchive }
        defer { try? handle.close() }
        try inflate(entry) { chunk in try handle.write(contentsOf: chunk) }
    }

    // MARK: Reading entries

    private func inflate(_ entry: Entry, into sink: (Data) throws -> Void) throws {
        guard entry.flags & 0x1 == 0 else { throw CaptureError.unsupportedArchiveEntry("encrypted") }
        guard entry.size <= Self.maxEntrySize, entry.compressedSize <= Self.maxEntrySize else { throw CaptureError.fileTooLarge }
        let start = try dataStart(of: entry)
        guard start + entry.compressedSize <= UInt64(data.count) else { throw CaptureError.damagedArchive }
        let range = Int(start)..<Int(start + entry.compressedSize)
        var crc = CRC32()
        var written: UInt64 = 0
        func counted(_ chunk: Data) throws {
            crc.update(chunk)
            written += UInt64(chunk.count)
            guard written <= entry.size else { throw CaptureError.damagedArchive }
            try sink(chunk)
        }
        switch entry.method {
        case 0:
            var offset = range.lowerBound
            while offset < range.upperBound {
                let end = min(offset + (1 << 20), range.upperBound)
                try counted(data.subdata(in: offset..<end))
                offset = end
            }
        case 8:
            try Self.inflateRaw(data, range: range, sink: counted)
        default:
            throw CaptureError.unsupportedArchiveEntry("method \(entry.method)")
        }
        guard written == entry.size, crc.value == entry.crc32 else { throw CaptureError.damagedArchive }
    }

    /// Raw DEFLATE (RFC 1951, no zlib header: what ZIP stores) through `compression_stream`.
    private static func inflateRaw(_ data: Data, range: Range<Int>, sink: (Data) throws -> Void) throws {
        let bufferSize = 256 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }
        var stream = compression_stream(dst_ptr: destination, dst_size: bufferSize, src_ptr: destination, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw CaptureError.damagedArchive
        }
        defer { compression_stream_destroy(&stream) }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { throw CaptureError.damagedArchive }
            stream.src_ptr = base.advanced(by: range.lowerBound)
            stream.src_size = range.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let remaining = stream.src_size
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { try sink(Data(bytes: destination, count: produced)) }
                switch status {
                case COMPRESSION_STATUS_END: return
                case COMPRESSION_STATUS_OK:
                    // No output and no input taken: the entry ends without its end marker (truncated).
                    if produced == 0, stream.src_size == remaining { throw CaptureError.damagedArchive }
                default: throw CaptureError.damagedArchive
                }
            }
        }
    }

    private func dataStart(of entry: Entry) throws -> UInt64 {
        let offset = Int(entry.localHeaderOffset)
        guard try data.uint32(at: offset) == 0x0403_4b50 else { throw CaptureError.damagedArchive }
        let nameLength = UInt64(try data.uint16(at: offset + 26))
        let extraLength = UInt64(try data.uint16(at: offset + 28))
        return entry.localHeaderOffset + 30 + nameLength + extraLength
    }

    // MARK: The central directory

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw CaptureError.damagedArchive }
        // The end-of-central-directory record is the last 22 bytes plus a comment of up to 64 KB.
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var eocd: Int?
        var position = data.count - 22
        while position >= lowest {
            if try data.uint32(at: position) == 0x0605_4b50 { eocd = position; break }
            position -= 1
        }
        guard let eocd else { throw CaptureError.damagedArchive }
        var count = UInt64(try data.uint16(at: eocd + 10))
        var directoryOffset = UInt64(try data.uint32(at: eocd + 16))
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            // ZIP64: the locator sits right before the classic record and points at the ZIP64 record.
            let locator = eocd - 20
            guard locator >= 0, try data.uint32(at: locator) == 0x0706_4b50 else { throw CaptureError.damagedArchive }
            let record = Int(try data.uint64(at: locator + 8))
            guard try data.uint32(at: record) == 0x0606_4b50 else { throw CaptureError.damagedArchive }
            count = try data.uint64(at: record + 32)
            directoryOffset = try data.uint64(at: record + 48)
        }
        guard count < 1_000_000 else { throw CaptureError.damagedArchive }
        var entries: [Entry] = []
        entries.reserveCapacity(Int(count))
        var offset = Int(directoryOffset)
        for _ in 0..<count {
            guard try data.uint32(at: offset) == 0x0201_4b50 else { throw CaptureError.damagedArchive }
            let flags = try data.uint16(at: offset + 8)
            let method = try data.uint16(at: offset + 10)
            let crc = try data.uint32(at: offset + 16)
            var compressed = UInt64(try data.uint32(at: offset + 20))
            var size = UInt64(try data.uint32(at: offset + 24))
            let nameLength = Int(try data.uint16(at: offset + 28))
            let extraLength = Int(try data.uint16(at: offset + 30))
            let commentLength = Int(try data.uint16(at: offset + 32))
            var localOffset = UInt64(try data.uint32(at: offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength + extraLength <= data.count else { throw CaptureError.damagedArchive }
            let nameBytes = data.subdata(in: nameStart..<nameStart + nameLength)
            let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
            // ZIP64 extra field: the 64-bit values, in this order, for each classic field that is 0xFFFFFFFF.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = try data.uint16(at: extra)
                let length = Int(try data.uint16(at: extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if size == 0xFFFF_FFFF { size = try data.uint64(at: field); field += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = try data.uint64(at: field); field += 8 }
                    if localOffset == 0xFFFF_FFFF { localOffset = try data.uint64(at: field) }
                }
                extra += 4 + length
            }
            entries.append(Entry(name: name, method: method, flags: flags, crc32: crc, compressedSize: compressed,
                                 size: size, localHeaderOffset: localOffset))
            offset = extraEnd + commentLength
        }
        return entries
    }
}

/// CRC-32 (IEEE 802.3, the one ZIP uses), table-driven.
struct CRC32 {
    private(set) var value: UInt32 = 0

    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    mutating func update(_ data: Data) {
        var c = ~value
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes { c = Self.table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        value = ~c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = CRC32()
        crc.update(data)
        return crc.value
    }
}

extension Data {
    /// Little-endian integers at a byte offset from the start, bounds-checked (a damaged archive throws, never traps).
    func uint16(at offset: Int) throws -> UInt16 { UInt16(truncatingIfNeeded: try littleEndian(at: offset, count: 2)) }
    func uint32(at offset: Int) throws -> UInt32 { UInt32(truncatingIfNeeded: try littleEndian(at: offset, count: 4)) }
    func uint64(at offset: Int) throws -> UInt64 { try littleEndian(at: offset, count: 8) }

    private func littleEndian(at offset: Int, count: Int) throws -> UInt64 {
        guard offset >= 0, offset + count <= self.count else { throw CaptureError.damagedArchive }
        var value: UInt64 = 0
        let base = startIndex + offset
        for i in (0..<count).reversed() { value = (value << 8) | UInt64(self[base + i]) }
        return value
    }
}
