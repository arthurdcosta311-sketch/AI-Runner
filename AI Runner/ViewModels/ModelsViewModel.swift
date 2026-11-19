//
//  ModelsViewModel.swift
//  AI Runner
//

import Foundation
import SwiftUI

/// A file stored in the app's Models folder.
struct LocalModelFile: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64
    /// "general.architecture" from the GGUF header, when the file has one.
    let architecture: String?

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isLanguageModel: Bool { url.pathExtension.lowercased() == "gguf" }
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    /// False for a model whose architecture the bundled engine cannot run.
    var isSupported: Bool {
        architecture.map { ModelSupport.isSupported($0) } ?? true
    }
}

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published private(set) var localFiles: [LocalModelFile] = []
    @Published var searchText = ""
    @Published private(set) var searchResults: [HFModel] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?
    @Published var importError: String?

    init() {
        refresh()
    }

    // MARK: - Local files

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: AppFolders.models,
                                                                 includingPropertiesForKeys: [.fileSizeKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
        localFiles = urls
            .map { url -> LocalModelFile in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                var architecture: String?
                if url.pathExtension.lowercased() == "gguf" {
                    architecture = (try? GGUFHeader.read(from: url))?.architecture
                }
                return LocalModelFile(url: url, sizeBytes: Int64(size), architecture: architecture)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func delete(_ file: LocalModelFile) {
        try? FileManager.default.removeItem(at: file.url)
        refresh()
    }

    func importFromFilesApp(_ url: URL) {
        importError = nil
        do {
            try FileStore.importFile(url, into: AppFolders.models)
            refresh()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Hugging Face search

    func search(token: String?) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            searchResults = try await HuggingFaceAPI.search(query, token: token)
        } catch {
            searchResults = []
            searchError = "The search failed. Check your connection and try again."
        }
    }
}
