//
//  GGUFHeader.swift
//  AI Runner
//

import Foundation

/// The start of a GGUF file: the format version, and the metadata that says which
/// model architecture the file holds. Read before loading so a file the engine
/// cannot run fails with a clear message instead of a bare engine error.
struct GGUFHeader {
    let version: Int
    let tensorCount: UInt64
    let metadataCount: UInt64
    /// "general.architecture", for example "llama", "qwen2" or "gemma2".
    let architecture: String?
    /// "general.name", when the file records one.
    let name: String?

    enum ReadError: Error {
        /// The file does not start with the GGUF signature.
        case notGGUF
        /// The header stops before it is complete, so the file is truncated.
        case truncated
    }

    static func read(from url: URL) throws -> GGUFHeader {
        // Only the first few megabytes are needed: the header keys come before the
        // tokenizer data, and a bounded read never pulls a multi-gigabyte model into memory.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8 * 1024 * 1024) ?? Data()
        var reader = Reader(data: data)

        guard let magic = reader.fixedString(count: 4), magic == "GGUF" else {
            throw ReadError.notGGUF
        }
        guard let version = reader.uint32(),
              let tensorCount = reader.uint64(),
              let metadataCount = reader.uint64() else {
            throw ReadError.truncated
        }

        var architecture: String?
        var name: String?
        // Real models carry megabytes of metadata after the keys we want, so read
        // only the first few hundred keys and stop as soon as the architecture is known.
        let limit = Int(min(metadataCount, 512))
        for _ in 0..<limit {
            guard let key = reader.string(), let type = reader.uint32() else { break }
            if key == "general.architecture", type == 8 {
                guard let value = reader.string() else { throw ReadError.truncated }
                architecture = value
            } else if key == "general.name", type == 8 {
                guard let value = reader.string() else { throw ReadError.truncated }
                name = value
            } else if !reader.skipValue(type: type) {
                // Metadata this reader cannot walk past: keep what was read so far.
                break
            }
            if architecture != nil { break }
        }

        return GGUFHeader(version: Int(version),
                          tensorCount: tensorCount,
                          metadataCount: metadataCount,
                          architecture: architecture,
                          name: name)
    }

    /// Reads GGUF's little-endian primitives out of the mapped file.
    private struct Reader {
        let data: Data
        var offset = 0

        init(data: Data) {
            self.data = data
        }

        mutating func fixedString(count: Int) -> String? {
            guard count >= 0, count <= data.count - offset else { return nil }
            let range = offset..<(offset + count)
            offset += count
            return String(decoding: data[range], as: UTF8.self)
        }

        mutating func uint32() -> UInt32? {
            guard 4 <= data.count - offset else { return nil }
            var value: UInt32 = 0
            for index in 0..<4 {
                value |= UInt32(data[offset + index]) << (8 * index)
            }
            offset += 4
            return value
        }

        mutating func uint64() -> UInt64? {
            guard 8 <= data.count - offset else { return nil }
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(data[offset + index]) << (8 * index)
            }
            offset += 8
            return value
        }

        mutating func string() -> String? {
            guard let length = uint64() else { return nil }
            // A model name or architecture never comes near this; anything longer
            // means the offset is wrong.
            guard length <= 4_000_000 else { return nil }
            return fixedString(count: Int(length))
        }

        mutating func advance(_ count: Int) -> Bool {
            guard count >= 0, count <= data.count - offset else { return false }
            offset += count
            return true
        }

        mutating func advance(_ count: UInt64, size: Int) -> Bool {
            guard count <= UInt64(Int.max / size) else { return false }
            return advance(Int(count) * size)
        }

        /// Walks past one metadata value of the given GGUF type.
        mutating func skipValue(type: UInt32) -> Bool {
            switch type {
            case 0, 1, 7:                 // uint8, int8, bool
                return advance(1)
            case 2, 3:                    // uint16, int16
                return advance(2)
            case 4, 5, 6:                 // uint32, int32, float32
                return advance(4)
            case 10, 11, 12:              // uint64, int64, float64
                return advance(8)
            case 8:                       // string
                return string() != nil
            case 9:                       // array
                guard let elementType = uint32(), let count = uint64() else { return false }
                return skipArray(type: elementType, count: count)
            default:
                return false
            }
        }

        mutating func skipArray(type: UInt32, count: UInt64) -> Bool {
            switch type {
            case 0, 1, 7:
                return advance(count, size: 1)
            case 2, 3:
                return advance(count, size: 2)
            case 4, 5, 6:
                return advance(count, size: 4)
            case 10, 11, 12:
                return advance(count, size: 8)
            case 8:
                // Strings carry their own length, so each one has to be stepped over.
                guard count <= 1_000_000 else { return false }
                for _ in 0..<count {
                    if string() == nil { return false }
                }
                return true
            default:
                return false
            }
        }
    }
}

/// Which model architectures the bundled llama.cpp can load.
enum ModelSupport {
    /// Architectures that arrived after the engine this app ships (llama.cpp
    /// b5046, April 2025). llama.cpp returns no model for these, which the
    /// engine wrapper reports as a meaningless "SwiftLlamaError error 0".
    static let unsupportedArchitectures: Set<String> = [
        "qwen3",
        "qwen3moe",
        "qwen3next",
        "llama4",
        "glm4",
        "gpt-oss",
        "deepseek3",
        "kimi-k2"
    ]

    static func isSupported(_ architecture: String) -> Bool {
        !unsupportedArchitectures.contains(architecture.lowercased())
    }

    /// A short reason for the Models screen, when the file cannot be loaded here.
    static func reason(for architecture: String) -> String {
        "This is a \(architecture) model. The engine built into this app is too old to run it."
    }
}
