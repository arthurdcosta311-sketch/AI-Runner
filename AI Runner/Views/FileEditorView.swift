//
//  FileEditorView.swift
//  AI Runner
//

import SwiftUI

/// Shows a text file and lets the user edit and save it. Other files show their details and can be shared.
struct FileEditorView: View {
    let url: URL

    @State private var text = ""
    @State private var saved = ""
    @State private var isEditing = false
    @State private var isText = true
    @State private var unavailableReason = ""
    @State private var errorText: String?
    @State private var loaded = false

    private var hasChanges: Bool { text != saved }

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            Group {
                if !isText {
                    ContentUnavailableView {
                        Label(url.lastPathComponent, systemImage: "doc")
                    } description: {
                        Text(unavailableReason)
                    } actions: {
                        ShareLink(item: url) {
                            Label("Share file", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.appPurple)
                    }
                } else if isEditing {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                } else {
                    ScrollView {
                        Text(text.isEmpty ? "(empty file)" : text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .animation(.smooth, value: isEditing)
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isText {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            text = saved
                            isEditing = false
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") { save() }
                            .disabled(!hasChanges)
                            .fontWeight(.semibold)
                    } else {
                        Button("Edit") { isEditing = true }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                ShareLink(item: url)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= 2_000_000 else {
            isText = false
            unavailableReason = "This file is \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)), too large to edit here. You can still share it."
            return
        }
        if let content = FileStore.readText(url) {
            text = content
            saved = content
        } else {
            isText = false
            unavailableReason = "This is not a text file, so it can't be edited here. You can share it instead."
        }
    }

    private func save() {
        do {
            try FileStore.writeText(text, to: url)
            saved = text
            isEditing = false
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
