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

    /// The prompt format a model file most likely expects, judged from its file name.
    static func guess(for fileName: String) -> PromptTemplate {
        let name = fileName.lowercased()
        if name.contains("llama-3") || name.contains("llama3") { return .llama3 }
        if name.contains("gemma") { return .gemma }
        if name.contains("phi") { return .phi }
        if name.contains("mistral") { return .mistral }
        return .chatML
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
    /// Lets the model use tools: FETCH, SEARCH, CURL, RUN JS, RUN LUA, GITHUB and MCP.
    @Published var webAccessEnabled: Bool { didSet { defaults.set(webAccessEnabled, forKey: "webAccessEnabled") } }
    @Published var jitDebugEnabled: Bool { didSet { defaults.set(jitDebugEnabled, forKey: "jitDebugEnabled") } }
    @Published var imageModel: String { didSet { defaults.set(imageModel, forKey: "imageModel") } }
    @Published var audioModel: String { didSet { defaults.set(audioModel, forKey: "audioModel") } }
    @Published var mcpServers: [MCPServer] {
        didSet {
            if let data = try? JSONEncoder().encode(mcpServers) {
                defaults.set(data, forKey: "mcpServers")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        systemPrompt = defaults.string(forKey: "systemPrompt")
            ?? "You are a helpful AI assistant running locally on this device. Be concise and accurate."
        template = PromptTemplate(rawValue: defaults.string(forKey: "template") ?? "") ?? .chatML
        contextSize = defaults.object(forKey: "contextSize") as? Int ?? 2048
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.2
        maxTokens = defaults.object(forKey: "maxTokens") as? Int ?? 1024
        webAccessEnabled = defaults.object(forKey: "webAccessEnabled") as? Bool ?? true
        jitDebugEnabled = defaults.bool(forKey: "jitDebugEnabled")
        imageModel = defaults.string(forKey: "imageModel") ?? "stabilityai/stable-diffusion-xl-base-1.0"
        audioModel = defaults.string(forKey: "audioModel") ?? "openai/whisper-large-v3-turbo"
        mcpServers = defaults.data(forKey: "mcpServers")
            .flatMap { try? JSONDecoder().decode([MCPServer].self, from: $0) } ?? []
    }

    /// The stored Hugging Face token, if the user has entered one.
    var huggingFaceToken: String? {
        ApiKeyManager.shared.get(key: "HUGGING_FACE_TOKEN")
    }

    var hasHuggingFaceToken: Bool {
        huggingFaceToken?.isEmpty == false
    }

    /// True when the user has saved a GitHub token in Integrations.
    var hasGitHubToken: Bool {
        ApiKeyManager.shared.has(key: "GITHUB_TOKEN")
    }

    func makeConfiguration() -> Configuration {
        let stopTokens: [String]
        switch template {
        case .chatML: stopTokens = ["<|im_end|>"]
        case .llama: stopTokens = ["[INST]", "</s>"]
        case .llama3: stopTokens = ["<|eot_id|>", "<|end_of_text|>"]
        case .mistral: stopTokens = ["</s>"]
        case .gemma: stopTokens = ["<end_of_turn>"]
        case .phi: stopTokens = ["<|end|>", "<|endoftext|>"]
        case .alpaca: stopTokens = []
        }

        // SwiftLlama decodes the whole prompt in one batch and counts it against a
        // hard 1024-token budget shared with the reply, so the context stays in a
        // range those limits can serve, and the reply never exceeds what is left.
        let context = min(4096, max(512, contextSize))
        return Configuration(
            nCTX: context,
            temperature: Float(temperature),
            batchSize: min(context * 2, 4096),
            maxTokenCount: min(512, max(64, maxTokens)),
            stopTokens: stopTokens
        )
    }
}
