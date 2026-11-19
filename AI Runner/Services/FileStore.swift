//
//  FileStore.swift
//  AI Runner
//

import Foundation

/// One item in a folder shown by the Files tab.
struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum FileStoreError: LocalizedError {
    case invalidName
    case exists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Use a name without slashes."
        case .exists(let name):
            return "\(name) already exists."
        }
    }
}

/// Reads, writes and organises the files the Files tab shows.
enum FileStore {
    static func list(_ folder: URL) -> [FileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                 includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls
            .map { url -> FileItem in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return FileItem(url: url,
                                isDirectory: values?.isDirectory ?? false,
                                size: Int64(values?.fileSize ?? 0))
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func createFile(named name: String, in folder: URL) throws {
        let url = try destination(for: name, in: folder)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FileStoreError.exists(name) }
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    static func createFolder(named name: String, in folder: URL) throws {
        let url = try destination(for: name, in: folder)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FileStoreError.exists(name) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    /// Copies a file picked in the Files app into `folder`.
    static func importFile(_ source: URL, into folder: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }
        let target = DownloadManager.uniqueURL(for: source.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: source, to: target)
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func readText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func destination(for name: String, in folder: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
            throw FileStoreError.invalidName
        }
        return folder.appendingPathComponent(trimmed)
    }
}
