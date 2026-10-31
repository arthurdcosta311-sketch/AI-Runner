//
//  AppSettings.swift
//  AI Runner
//

import Foundation
import SwiftLlama

/// Prompt formats understood by the local engine.
enum PromptTemplate: String, CaseIterable, Identifiable {
    case chatML = "ChatML"
    case llama = "Llama 2"
    case llama3 = "Llama 3"
    case mistral = "Mistral"
    case gemma = "Gemma"
    case phi = "Phi"
    case alpaca = "Alpaca"

    var id: String { rawValue }

    var promptType: Prompt.`Type` {
        switch self {
        case .chatML: return .chatML
        case .llama: return .llama
        case .llama3: return .llama3
        case .mistral: return .mistral
        case .gemma: return .gemma
        case .phi: return .phi
        case .alpaca: return .alpaca
        }
    }
}

/// App-wide settings persisted in UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "systemPrompt") } }
    @Published var template: PromptTemplate { didSet { defaults.set(template.rawValue, forKey: "template") } }
    @Published var contextSize: Int { didSet { defaults.set(contextSize, forKey: "contextSize") } }
    @Published var temperature: Double { didSet { defaults.set(temperature, forKey: "temperature") } }
    @Published var maxTokens: Int { didSet { defaults.set(maxTokens, forKey: "maxTokens") } }
    @Published var webAccessEnabled: Bool { didSet { defaults.set(webAccessEnabled, forKey: "webAccessEnabled") } }
    @Published var jitDebugEnabled: Bool { didSet { defaults.set(jitDebugEnabled, forKey: "jitDebugEnabled") } }
    @Published var imageModel: String { didSet { defaults.set(imageModel, forKey: "imageModel") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        systemPrompt = defaults.string(forKey: "systemPrompt")
            ?? "You are a helpful AI assistant running locally on this device. Be concise and accurate."
        template = PromptTemplate(rawValue: defaults.string(forKey: "template") ?? "") ?? .chatML
        contextSize = defaults.object(forKey: "contextSize") as? Int ?? 2048
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.2
        maxTokens = defaults.object(forKey: "maxTokens") as? Int ?? 1024
        webAccessEnabled = defaults.bool(forKey: "webAccessEnabled")
        jitDebugEnabled = defaults.bool(forKey: "jitDebugEnabled")
        imageModel = defaults.string(forKey: "imageModel") ?? "stabilityai/stable-diffusion-xl-base-1.0"
    }

    /// The stored Hugging Face token, if the user has entered one.
    var huggingFaceToken: String? {
        ApiKeyManager.shared.get(key: "HUGGING_FACE_TOKEN")
    }

    var hasHuggingFaceToken: Bool {
        huggingFaceToken?.isEmpty == false
    }

    func makeConfiguration() -> Configuration {
        var stopTokens: [String] = []
        if template == .chatML { stopTokens = ["<|im_end|>"] }
        if template == .llama { stopTokens = ["[INST]"] }
        if template == .gemma { stopTokens = ["<end_of_turn>"] }
        if template == .phi { stopTokens = ["<|end|>"] }

        return Configuration(
            nCTX: max(256, contextSize),
            temperature: Float(temperature),
            maxTokenCount: max(64, maxTokens),
            stopTokens: stopTokens
        )
    }
}