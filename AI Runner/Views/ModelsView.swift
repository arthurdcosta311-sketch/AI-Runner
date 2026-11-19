//
//  ModelsView.swift
//  AI Runner
//

import SwiftUI
import UniformTypeIdentifiers

/// The Models tab: the Hugging Face token, models to download, Hugging Face search and the files on this phone.
struct ModelsView: View {
    @ObservedObject var runner: LlamaRunner
    @ObservedObject var modelsViewModel: ModelsViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject private var manager = DownloadManager.shared

    @State private var showingImporter = false
    @State private var tokenDraft = ""
    @State private var hasToken = false

    var body: some View {
        NavigationStack {
            List {
                tokenSection
                loadedSection
                DownloadsSection()
                languageSection
                searchSection
                speechSection
                localSection

                if let error = modelsViewModel.importError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import a model file")
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [UTType.data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    modelsViewModel.importFromFilesApp(url)
                }
            }
            .onAppear {
                modelsViewModel.refresh()
                hasToken = settings.hasHuggingFaceToken
            }
            .onChange(of: manager.finishedCount) { _, _ in
                modelsViewModel.refresh()
            }
            .animation(.smooth, value: modelsViewModel.localFiles.count)
        }
    }

    // MARK: - Sections

    private var tokenSection: some View {
        Section {
            Label(hasToken ? "Token saved in the keychain" : "No token yet",
                  systemImage: hasToken ? "checkmark.seal.fill" : "key")
                .foregroundStyle(hasToken ? Color.appPurple : Color.secondary)
            SecureField("Paste your Hugging Face token", text: $tokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save token") {
                let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { return }
                ApiKeyManager.shared.set(key: "HUGGING_FACE_TOKEN", value: token)
                tokenDraft = ""
                hasToken = true
            }
            .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            if hasToken {
                Button("Remove token", role: .destructive) {
                    ApiKeyManager.shared.remove(key: "HUGGING_FACE_TOKEN")
                    hasToken = false
                }
            }
        } header: {
            Text("Hugging Face token")
        } footer: {
            Text("With a token you can download gated models, search every GGUF model on Hugging Face, and use the hosted image and speech models. Create one at huggingface.co/settings/tokens.")
        }
    }

    private var loadedSection: some View {
        Section {
            if runner.isLoadingModel, let name = runner.loadingModelName {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.appPurple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loading \(name)")
                            .font(.subheadline.weight(.semibold))
                        Text("Reading the weights and building the context. This takes a few seconds, and the app stays usable meanwhile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if runner.isModelLoaded {
                LabeledContent("Loaded", value: runner.loadedModelName ?? "Unknown")
                Button("Unload model", role: .destructive) {
                    runner.unload()
                }
            } else if !runner.isLoadingModel {
                Text("No language model loaded. Download one below, then tap Load.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Language model")
        }
    }

    private var languageSection: some View {
        Section {
            ForEach(ModelCatalog.language) { model in
                catalogRow(model)
            }
        } header: {
            Text("Download")
        } footer: {
            Text("Models download straight to this phone, with no size limit. Tap Load under On this phone to chat with one. Only models the app's built-in engine can run are listed: files from newer architectures, such as Qwen 3 or Llama 4, cannot be loaded here.")
        }
    }

    private var searchSection: some View {
        Section {
            HStack {
                TextField("Search Hugging Face, e.g. qwen", text: $modelsViewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await modelsViewModel.search(token: settings.huggingFaceToken) }
                    }
                if modelsViewModel.isSearching {
                    ProgressView()
                }
            }
            ForEach(modelsViewModel.searchResults) { model in
                NavigationLink {
                    RepoFilesView(repo: model.id, settings: settings)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.id)
                            .lineLimit(1)
                        Text("\(model.downloads) downloads")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let error = modelsViewModel.searchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Find more models")
        } footer: {
            Text("Shows GGUF models from Hugging Face. Pick one to see its files, then download the one you want.")
        }
    }

    private var speechSection: some View {
        Section {
            ForEach(ModelCatalog.audio.filter { $0.file != nil }) { model in
                catalogRow(model)
            }
        } header: {
            Text("Speech files")
        } footer: {
            Text("Speech files are saved to this phone. Running them on the phone needs a speech engine the app doesn't have yet. Hosted speech-to-text is under Create.")
        }
    }

    private var localSection: some View {
        Section {
            if modelsViewModel.localFiles.isEmpty {
                Text("No files yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(modelsViewModel.localFiles) { file in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(2)
                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let architecture = file.architecture, !file.isSupported {
                            Text(ModelSupport.reason(for: architecture))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if file.isLanguageModel {
                        let isLoaded = runner.loadedModelName == file.name
                        let isLoadingThis = runner.loadingModelName == file.name
                        if isLoadingThis {
                            ProgressView()
                                .tint(.appPurple)
                        } else {
                            Button(isLoaded ? "Loaded" : "Load") {
                                Task {
                                    do {
                                        settings.template = PromptTemplate.guess(for: file.name)
                                        try await runner.loadModel(at: file.url, settings: settings)
                                    } catch {
                                        modelsViewModel.importError = error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.appPurple)
                            .disabled(isLoaded || !file.isSupported || runner.isLoadingModel)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        if runner.loadedModelName == file.name {
                            runner.unload()
                        }
                        modelsViewModel.delete(file)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("On this phone")
        }
    }

    // MARK: - Rows

    private func catalogRow(_ model: CatalogModel) -> some View {
        let fileName = model.file ?? ""
        let active = manager.downloads.first { $0.name == fileName && $0.state == .running }
        let installed = modelsViewModel.localFiles.contains { $0.name == fileName }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.headline)
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.approximateSize)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let active {
                ProgressView(value: active.progress)
                    .progressViewStyle(.circular)
                    .tint(.appPurple)
            } else if installed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.appPurple)
            } else {
                Button {
                    download(model)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .tint(.appPurple)
                .accessibilityLabel("Download \(model.title)")
            }
        }
    }

    private func download(_ model: CatalogModel) {
        guard let url = model.downloadURL else { return }
        DownloadManager.shared.start(url, into: AppFolders.models, token: settings.huggingFaceToken)
    }
}

/// The files of one Hugging Face repository, with a download button for each GGUF file.
private struct RepoFilesView: View {
    let repo: String
    @ObservedObject var settings: AppSettings

    @State private var files: [HFFile] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !isLoading && files.isEmpty && errorText == nil {
                Section {
                    Text("No GGUF files in this repository.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(files) { file in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .lineLimit(2)
                            if file.size > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            download(file)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .tint(.appPurple)
                        .accessibilityLabel("Download \(file.name)")
                    }
                }
            }
        }
        .navigationTitle(repo.components(separatedBy: "/").last ?? repo)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            files = try await HuggingFaceAPI.ggufFiles(repo: repo, token: settings.huggingFaceToken)
            errorText = nil
        } catch {
            errorText = "Could not list the files. Gated models need your Hugging Face token: \(error.localizedDescription)"
        }
    }

    private func download(_ file: HFFile) {
        guard let url = file.downloadURL(repo: repo) else { return }
        DownloadManager.shared.start(url, into: AppFolders.models, token: settings.huggingFaceToken)
    }
}
