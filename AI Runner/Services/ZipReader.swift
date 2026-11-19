//
//  ZipReader.swift
//  AI Runner
//

import Foundation
import Compression

enum ZipError: LocalizedError {
    case notAnArchive
    case corrupt(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "That download wasn't a readable archive."
        case .corrupt(let detail):
            return "The archive is damaged: \(detail)"
        case .unsupported(let detail):
            return "The archive can't be unpacked here: \(detail)"
        }
    }
}

/// One file in a ZIP archive, as listed in its central directory.
struct ZipEntry {
    let name: String
    let compressionMethod: Int
    let compressedSize: Int
    let uncompressedSize: Int
    let headerOffset: Int
}

/// Reads ZIP archives: enough of the format to unpack a repository downloaded from
/// GitHub. Files are stored (method 0) or deflated (method 8), which is everything
/// the archives used here contain. It never touches the network or the file system
/// until `extractAll(into:)` writes the files it found.
struct ZipArchive {
    private let bytes: Data
    let entries: [ZipEntry]

    init(data: Data) throws {
        bytes = data
        entries = try Self.readCentralDirectory(data)
    }

    /// Unpacks every file into `directory`, dropping the single top-level folder an
    /// archive like GitHub's adds. Returns how many files were written.
    @discardableResult
    func extractAll(into directory: URL) throws -> Int {
        let fileManager = FileManager.default
        let prefix = Self.sharedRoot(of: entries.map(\.name))
        var written = 0

        for entry in entries where !entry.name.hasSuffix("/") {
            var name = entry.name
            if let prefix, name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
            }
            guard !name.isEmpty else { continue }
            guard Self.isSafe(path: name) else {
                throw ZipError.unsupported("it contains a path outside the folder (\(name)).")
            }

            let target = directory.appendingPathComponent(name)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try contents(of: entry).write(to: target, options: .atomic)
            written += 1
        }
        return written
    }

    /// One entry's file contents, decompressed.
    func contents(of entry: ZipEntry) throws -> Data {
        guard Self.uint32(bytes, entry.headerOffset) == 0x0403_4b50,
              let nameLength = Self.uint16(bytes, entry.headerOffset + 26),
              let extraLength = Self.uint16(bytes, entry.headerOffset + 28) else {
            throw ZipError.corrupt("a file header could not be read.")
        }
        let start = entry.headerOffset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count, start <= end else {
            throw ZipError.corrupt("a file runs past the end of the archive.")
        }
        let raw = bytes.subdata(in: start..<end)

        switch entry.compressionMethod {
        case 0:
            return raw
        case 8:
            return try Self.inflate(raw, size: entry.uncompressedSize)
        default:
            throw ZipError.unsupported("it uses compression method \(entry.compressionMethod).")
        }
    }

    // MARK: - Reading

    private static func readCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        guard let end = endOfCentralDirectory(data) else { throw ZipError.notAnArchive }
        guard let count = uint16(data, end + 10),
              let directoryOffset = uint32(data, end + 16),
              let directorySize = uint32(data, end + 12) else {
            throw ZipError.corrupt("the archive's index could not be read.")
        }
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF || directorySize == 0xFFFF_FFFF {
            throw ZipError.unsupported("it uses the large-archive format.")
        }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(count)
        var offset = directoryOffset

        for _ in 0..<count {
            guard uint32(data, offset) == 0x0201_4b50,
                  let method = uint16(data, offset + 10),
                  let compressed = uint32(data, offset + 20),
                  let uncompressed = uint32(data, offset + 24),
                  let nameLength = uint16(data, offset + 28),
                  let extraLength = uint16(data, offset + 30),
                  let commentLength = uint16(data, offset + 32),
                  let headerOffset = uint32(data, offset + 42) else {
                throw ZipError.corrupt("a file in the index could not be read.")
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else { throw ZipError.corrupt("a file name runs past the end of the archive.") }
            let name = String(decoding: data.subdata(in: nameStart..<nameEnd), as: UTF8.self)

            entries.append(ZipEntry(name: name,
                                    compressionMethod: method,
                                    compressedSize: compressed,
                                    uncompressedSize: uncompressed,
                                    headerOffset: headerOffset))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The offset of the archive's end record, found by scanning back from its end.
    private static func endOfCentralDirectory(_ data: Data) -> Int? {
        let recordSize = 22
        guard data.count >= recordSize else { return nil }
        let furthestBack = min(data.count - recordSize, 65_535)
        for back in 0...furthestBack {
            let offset = data.count - recordSize - back
            if uint32(data, offset) == 0x0605_4b50 { return offset }
        }
        return nil
    }

    private static func uint16(_ data: Data, _ offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let base = data.startIndex + offset
        return Int(data[base]) | Int(data[base + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        let value = Int(data[base])
            | Int(data[base + 1]) << 8
            | Int(data[base + 2]) << 16
            | Int(data[base + 3]) << 24
        return value
    }

    /// Decompresses one raw DEFLATE stream into a buffer of the known size.
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !input.isEmpty else { throw ZipError.corrupt("a file has no data.") }

        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            input.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let sourceBase = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(destinationBase, size,
                                                 sourceBase, input.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else {
            throw ZipError.corrupt("a file could not be decompressed.")
        }
        return output
    }

    /// The single folder every entry sits in ("repo-main/"), which is dropped on extract.
    private static func sharedRoot(of names: [String]) -> String? {
        var root: String?
        for name in names where !name.isEmpty {
            guard let slash = name.firstIndex(of: "/") else { return nil }
            let component = String(name[..<slash])
            if let root, root != component { return nil }
            root = component
        }
        guard let root, !root.isEmpty else { return nil }
        return root + "/"
    }

    /// Rejects absolute paths and any "..", so an archive can't write outside its folder.
    private static func isSafe(path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        return !path.split(separator: "/").contains("..")
    }
}
