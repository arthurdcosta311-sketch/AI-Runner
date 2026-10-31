//
//  ModelsView.swift
//  AI Runner
//

import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @ObservedObject var runner: LlamaRunner
    @ObservedObject var modelsViewModel: ModelsViewModel
    @ObservedObject var settings: AppSettings

    @State private var showingImporter = false
    @State private var importedURL: URL?

    var body: some View {
        NavigationStack {
            List {
                loadedSection
                downloadsSection
                modelsSection
                addModelSection
                if let error = modelsViewModel.importError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importedURL = nil
                        showingImporter = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Import a GGUF file")
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [UTType.data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    modelsViewModel.importFromFilesApp(url, securityScoped: true)
                }
            }
            .onAppear { modelsViewModel.refresh() }
        }
    }

    // MARK: - Sections

    private var loadedSection: some View {
        Section("Loaded model") {
            if runner.isModelLoaded {
                LabeledContent("Model", value: runner.loadedModelName ?? "Unknown")
                Button("Unload model", role: .destructive) {
                    runner.unload()
                }
            } else {
                ContentUnavailableView("No model loaded",
                                       systemImage: "cube.transparent",
                                       description: Text("Load a GGUF model below to run it on-device."))
            }
        }
    }

    private var downloadsSection: some View {
        Section("Downloads") {
            if modelsViewModel.downloader.items.isEmpty {
                Text("No downloads yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(modelsViewModel.downloader.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.fileName).lineLimit(1)
                    switch item.state {
                    case .downloading:
                        ProgressView(value: item.progress) {
                            if item.totalBytes > 0 {
                                Text("\(ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .finished:
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .waiting:
                        Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var modelsSection: some View {
        Section("Your GGUF models") {
            if modelsViewModel.models.isEmpty {
                Text("Download a model or import one with the folder button.")
                    .foregroundStyle(.secondary)
            }
            ForEach(modelsViewModel.models) { model in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name).lineLimit(2)
                            Text(model.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Load") {
                            do {
                                try runner.loadModel(at: model.url, settings: settings)
                            } catch {
                                modelsViewModel.importError = error.localizedDescription
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    HStack {
                        Spacer()
                        Button("Delete", role: .destructive) {
                            runner.unload()
                            modelsViewModel.delete(model)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var addModelSection: some View {
        Section {
            TextField("https://huggingface.co/…/model.gguf", text: $modelsViewModel.newModelURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                modelsViewModel.downloadFromTextField(settings: settings)
            } label: {
                Label("Download model", systemImage: "arrow.down.circle")
            }
        } header: {
            Text("Download from a URL")
        } footer: {
            Text(settings.hasHuggingFaceToken
                 ? "Your Hugging Face token is used for gated models."
                 : "Tip: add a Hugging Face token in Settings to download gated models.")
        }
    }
}