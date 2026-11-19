//
//  FilesView.swift
//  AI Runner
//

import SwiftUI
import UniformTypeIdentifiers

/// The Files tab: browse, view, edit and download files in the app's Documents folder.
struct FilesView: View {
    var body: some View {
        NavigationStack {
            FolderView(folder: AppFolders.documents, title: "Files")
        }
    }
}

/// One folder in the Files tab.
struct FolderView: View {
    let folder: URL
    let title: String

    @ObservedObject private var manager = DownloadManager.shared
    @State private var items: [FileItem] = []
    @State private var showingNewFile = false
    @State private var showingNewFolder = false
    @State private var showingDownload = false
    @State private var showingImporter = false
    @State private var newName = ""
    @State private var errorText: String?

    var body: some View {
        List {
            DownloadsSection()

            Section {
                if items.isEmpty {
                    Text("This folder is empty. Use + to add a file, download one from the internet or import one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    NavigationLink {
                        if item.isDirectory {
                            FolderView(folder: item.url, title: item.name)
                        } else {
                            FileEditorView(url: item.url)
                        }
                    } label: {
                        FileRow(item: item)
                    }
                }
                .onDelete(perform: delete)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = ""
                        showingNewFile = true
                    } label: {
                        Label("New file", systemImage: "doc.badge.plus")
                    }
                    Button {
                        newName = ""
                        showingNewFolder = true
                    } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showingDownload = true
                    } label: {
                        Label("Download from internet", systemImage: "arrow.down.circle")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from Files app", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
        }
        .alert("New file", isPresented: $showingNewFile) {
            TextField("notes.txt", text: $newName)
            Button("Create") { createFile() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingDownload) {
            DownloadSheet(folder: folder)
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .onAppear(perform: reload)
        .onChange(of: manager.finishedCount) { _, _ in reload() }
    }

    private func reload() {
        items = FileStore.list(folder)
    }

    private func createFile() {
        do {
            try FileStore.createFile(named: newName, in: folder)
            errorText = nil
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func createFolder() {
        do {
            try FileStore.createFolder(named: newName, in: folder)
            errorText = nil
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            do {
                try FileStore.delete(items[index].url)
            } catch {
                errorText = error.localizedDescription
            }
        }
        reload()
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    try FileStore.importFile(url, into: folder)
                } catch {
                    errorText = error.localizedDescription
                }
            }
            reload()
        }
    }
}

private struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.appPurple)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        if item.isDirectory { return "Folder" }
        return ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
    }

    private var symbol: String {
        if item.isDirectory { return "folder.fill" }
        switch item.url.pathExtension.lowercased() {
        case "gguf", "bin":
            return "cube"
        case "txt", "md", "json", "js", "lua", "swift", "csv", "html", "css", "vela", "c", "h", "m",
             "py", "xml", "yml", "yaml", "plist", "log":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return "photo"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return "waveform"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}

/// Downloads a file from a web address into a folder. There is no size cap.
struct DownloadSheet: View {
    let folder: URL

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/file.zip", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Any file, any size. It downloads in the background and is saved to this folder.")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") { start() }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func start() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            errorText = "Enter a web address that starts with https://."
            return
        }
        DownloadManager.shared.start(url, into: folder)
        dismiss()
    }
}
