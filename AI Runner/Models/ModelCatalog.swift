//
//  ModelCatalog.swift
//  AI Runner
//

import Foundation

/// The kind of model a catalog entry is.
enum ModelKind: String, CaseIterable, Identifiable {
    case language = "Language"
    case image = "Image"
    case audio = "Audio"

    var id: String { rawValue }
}

/// A model listed in the app. Entries with a `file` download to the phone.
/// Entries without one run on Hugging Face's hosted inference with the user's token.
struct CatalogModel: Identifiable, Hashable {
    let title: String
    let detail: String
    let kind: ModelKind
    /// The Hugging Face repository, or the model id for hosted models.
    let repo: String
    /// The file to download from the repository, when the model is downloaded.
    let file: String?
    let approximateSize: String

    var id: String { repo + (file.map { "/" + $0 } ?? "") }

    var downloadURL: URL? {
        guard let file else { return nil }
        return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)?download=true")
    }
}

enum ModelCatalog {
    static let language: [CatalogModel] = [
        CatalogModel(title: "Qwen 3 4B",
                     detail: "Qwen's strongest small model. Good reasoning and chat.",
                     kind: .language,
                     repo: "Qwen/Qwen3-4B-GGUF",
                     file: "Qwen3-4B-Q4_K_M.gguf",
                     approximateSize: "about 2.5 GB"),
        CatalogModel(title: "Qwen 3 1.7B",
                     detail: "Small and quick, for older phones. 8-bit quality.",
                     kind: .language,
                     repo: "Qwen/Qwen3-1.7B-GGUF",
                     file: "Qwen3-1.7B-Q8_0.gguf",
                     approximateSize: "about 1.8 GB"),
        CatalogModel(title: "Qwen 2.5 3B Instruct",
                     detail: "Solid multilingual chat and instruction following.",
                     kind: .language,
                     repo: "Qwen/Qwen2.5-3B-Instruct-GGUF",
                     file: "qwen2.5-3b-instruct-q4_k_m.gguf",
                     approximateSize: "about 2.0 GB"),
        CatalogModel(title: "Llama 3.2 3B Instruct",
                     detail: "Meta's compact chat model.",
                     kind: .language,
                     repo: "bartowski/Llama-3.2-3B-Instruct-GGUF",
                     file: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                     approximateSize: "about 2.0 GB"),
        CatalogModel(title: "Gemma 2 2B Instruct",
                     detail: "Google's small chat model.",
                     kind: .language,
                     repo: "bartowski/gemma-2-2b-it-GGUF",
                     file: "gemma-2-2b-it-Q4_K_M.gguf",
                     approximateSize: "about 1.6 GB"),
    ]

    static let image: [CatalogModel] = [
        CatalogModel(title: "Stable Diffusion XL",
                     detail: "Detailed images at high resolution.",
                     kind: .image,
                     repo: "stabilityai/stable-diffusion-xl-base-1.0",
                     file: nil,
                     approximateSize: "Hosted"),
        CatalogModel(title: "Stable Diffusion 1.5",
                     detail: "Fast and light, classic look.",
                     kind: .image,
                     repo: "stable-diffusion-v1-5/stable-diffusion-v1-5",
                     file: nil,
                     approximateSize: "Hosted"),
        CatalogModel(title: "FLUX.1 schnell",
                     detail: "Quick, sharp images from Black Forest Labs.",
                     kind: .image,
                     repo: "black-forest-labs/FLUX.1-schnell",
                     file: nil,
                     approximateSize: "Hosted"),
    ]

    static let audio: [CatalogModel] = [
        CatalogModel(title: "Whisper large v3 turbo",
                     detail: "Accurate speech-to-text, hosted.",
                     kind: .audio,
                     repo: "openai/whisper-large-v3-turbo",
                     file: nil,
                     approximateSize: "Hosted"),
        CatalogModel(title: "Whisper small",
                     detail: "Speech model file, saved to this phone.",
                     kind: .audio,
                     repo: "ggerganov/whisper.cpp",
                     file: "ggml-small.bin",
                     approximateSize: "about 470 MB"),
        CatalogModel(title: "Whisper base",
                     detail: "Smaller speech model file, saved to this phone.",
                     kind: .audio,
                     repo: "ggerganov/whisper.cpp",
                     file: "ggml-base.bin",
                     approximateSize: "about 150 MB"),
    ]
}
