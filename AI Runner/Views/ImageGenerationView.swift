//
//  ImageGenerationView.swift
//  AI Runner
//

import SwiftUI

struct ImageGenerationView: View {
    @ObservedObject var settings: AppSettings

    @State private var prompt = ""
    @State private var resultImage: UIImage?
    @State private var isGenerating = false
    @State private var errorText: String?
    @State private var shareImage: UIImage?

    private let service = ImageGenerationService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Describe the image to generate", text: $prompt, axis: .vertical)
                        .lineLimit(2...5)
                    Button {
                        generate()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .tint(.appAmber)
                            }
                            Label(isGenerating ? "Generating…" : "Generate image",
                                  systemImage: "paintbrush")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating || prompt.isEmpty)
                    .listRowBackground(Color.appAmber.opacity(0.9))
                    .foregroundStyle(.black)
                } footer: {
                    Text("A local GGUF model can't paint pictures, so image generation runs through the Hugging Face Inference API — only possible when the AI backend supports it.")
                }

                Section("Image model") {
                    TextField("stabilityai/stable-diffusion-xl-base-1.0", text: $settings.imageModel)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let resultImage {
                    Section("Result") {
                        Image(uiImage: resultImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                            .contextMenu {
                                ShareLink(item: Image(uiImage: resultImage), preview: SharePreview(prompt))
                            }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Image")
        }
    }

    private func generate() {
        errorText = nil
        resultImage = nil
        isGenerating = true
        let currentPrompt = prompt
        let model = settings.imageModel
        let token = settings.huggingFaceToken
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let image = try await service.generate(prompt: currentPrompt, model: model, token: token)
                resultImage = image
                shareImage = image
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}