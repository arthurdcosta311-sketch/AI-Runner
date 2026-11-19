//
//  CreateView.swift
//  AI Runner
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Create tab: image generation and speech-to-text, with the hosted models listed in the app.
struct CreateView: View {
    @ObservedObject var settings: AppSettings
    @State private var mode: Mode = .image

    enum Mode: String, CaseIterable, Identifiable {
        case image = "Image"
        case audio = "Audio"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    switch mode {
                    case .image:
                        ImagePanel(settings: settings)
                    case .audio:
                        AudioPanel(settings: settings)
                    }
                }
                .id(mode)
                .transition(.opacity)
            }
            .navigationTitle("Create")
            .animation(.smooth, value: mode)
        }
    }
}

private struct ImagePanel: View {
    @ObservedObject var settings: AppSettings

    @State private var prompt = ""
    @State private var result: UIImage?
    @State private var isGenerating = false
    @State private var errorText: String?

    private let service = ImageGenerationService()

    var body: some View {
        Form {
            Section {
                TextField("Describe the image", text: $prompt, axis: .vertical)
                    .lineLimit(2...5)
                Button {
                    generate()
                } label: {
                    HStack {
                        Spacer()
                        if isGenerating {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Text(isGenerating ? "Generating…" : "Generate image")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Prompt")
            } footer: {
                Text("Images come from the hosted model you choose, through Hugging Face with your token. A phone language model can't paint.")
            }

            Section {
                ForEach(ModelCatalog.image) { model in
                    Button {
                        settings.imageModel = model.repo
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.title)
                                Text(model.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.imageModel == model.repo {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.appPurple)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                TextField("Or type a model id", text: $settings.imageModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Image model")
            }

            if let result {
                Section {
                    Image(uiImage: result)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity)
                    ShareLink(item: Image(uiImage: result), preview: SharePreview(prompt)) {
                        Label("Share image", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Result")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .animation(.smooth, value: result != nil)
    }

    private func generate() {
        errorText = nil
        result = nil
        isGenerating = true
        let currentPrompt = prompt
        let model = settings.imageModel
        let token = settings.huggingFaceToken
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                result = try await service.generate(prompt: currentPrompt, model: model, token: token)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct AudioPanel: View {
    @ObservedObject var settings: AppSettings

    @State private var showingImporter = false
    @State private var audio: Data?
    @State private var audioType = "audio/wav"
    @State private var fileName: String?
    @State private var transcript = ""
    @State private var isWorking = false
    @State private var errorText: String?

    private let service = AudioTranscriptionService()

    var body: some View {
        Form {
            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label(fileName ?? "Choose an audio file", systemImage: "waveform")
                }
                Button {
                    transcribe()
                } label: {
                    Label(isWorking ? "Transcribing…" : "Transcribe", systemImage: "text.bubble")
                        .fontWeight(.semibold)
                }
                .disabled(audio == nil || isWorking)
            } header: {
                Text("Audio")
            } footer: {
                Text("Pick a recording from Files. It is sent to the speech model you choose, with your Hugging Face token.")
            }

            Section {
                ForEach(ModelCatalog.audio.filter { $0.file == nil }) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                            Text(model.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.audioModel == model.repo {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.appPurple)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.audioModel = model.repo
                    }
                }
                TextField("Or type a model id", text: $settings.audioModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Speech model")
            }

            if !transcript.isEmpty {
                Section {
                    Text(transcript)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = transcript
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("Transcript")
                }
                .transition(.opacity)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .animation(.smooth, value: transcript.isEmpty)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
            loadAudio(result)
        }
    }

    private func loadAudio(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                audio = try Data(contentsOf: url)
                audioType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "audio/wav"
                fileName = url.lastPathComponent
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func transcribe() {
        guard let audio else { return }
        isWorking = true
        errorText = nil
        let model = settings.audioModel
        let token = settings.huggingFaceToken
        let type = audioType
        Task { @MainActor in
            defer { isWorking = false }
            do {
                transcript = try await service.transcribe(audio, contentType: type, model: model, token: token)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
