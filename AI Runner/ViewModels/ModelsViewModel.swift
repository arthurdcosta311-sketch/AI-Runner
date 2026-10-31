//
//  ModelsViewModel.swift
//  AI Runner
//

import Foundation
import SwiftUI

/// A GGUF model file stored in the app's Documents/Models folder.
struct ModelFile: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    let sizeBytes: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published private(set) var models: [ModelFile] = []
    @Published var newModelURL: String = ""
    @Published var importError: String?

    let downloader = HFDownloader()

    init() {
        refresh()
    }

    // MARK: - Local models

    func refresh() {
        let directory = HFDownloader.modelsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)) ?? []
        models = files
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return ModelFile(id: UUID(), name: url.lastPathComponent, url: url, sizeBytes: Int64(size))
            }
            .sorted { $0.name < $1.name }
    }

    func delete(_ model: ModelFile) {
        try? FileManager.default.removeItem(at: model.url)
        refresh()
    }

    // MARK: - Downloads

    func downloadFromTextField(settings: AppSettings, completion: (() -> Void)? = nil) {
        let text = newModelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        importError = nil
        guard let url = URL(string: text), url.scheme == "http" || url.scheme == "https" else {
            importError = "Enter a valid http(s) URL to a .gguf file."
            return
        }
        download(from: url, token: settings.huggingFaceToken, completion: completion)
    }

    func download(from url: URL, token: String?, completion: (() -> Void)? = nil) {
        downloader.startDownload(from: url, token: token) { [weak self] result in
            switch result {
            case .success:
                self?.refresh()
            case .failure(let error):
                self?.importError = error.localizedDescription
            }
            completion?()
        }
    }

    func importFromFilesApp(_ url: URL, securityScoped: Bool) {
        importError = nil
        let destination = HFDownloader.modelsDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            if securityScoped { _ = url.startAccessingSecurityScopedResource() }
            defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            refresh()
        } catch {
            importError = error.localizedDescription
        }
    }
}