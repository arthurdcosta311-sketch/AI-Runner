//
//  LlamaRunner.swift
//  AI Runner
//

import Foundation
import MachO
import SwiftLlama

enum LlamaRunnerError: LocalizedError {
    case noModel
    case missingFile(String)
    case notGGUF(String)
    case unsupportedArchitecture(fileName: String, architecture: String)
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModel:
            return "No model is loaded. Download or import a GGUF model in the Models tab."
        case .missingFile(let name):
            return "\(name) is not on this phone any more. Download it again in the Models tab."
        case .notGGUF(let name):
            return "\(name) is not a GGUF model file. If it came from Hugging Face, download the .gguf file from the repository's file list."
        case .unsupportedArchitecture(let fileName, let architecture):
            return "\(fileName) is a \(architecture) model, and the engine built into this app is too old to run it. Download one of the models listed in the Models tab instead; those all load here."
        case .engineFailed(let fileName):
            return "\(fileName) could not be loaded. The file may be incomplete or damaged, or the model may be too large for this phone's memory. Delete it, download it again, or try a smaller model."
        }
    }
}

enum JITStatus {
    case available
    case denied
    case unknown
}

/// Runs a local GGUF model through llama.cpp.
final class LlamaRunner: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelName: String?
    @Published private(set) var lastDiagnostics: String = ""

    private var llama: SwiftLlama?
    private var loadedPath: String?

    // MARK: - Model lifecycle

    /// Checks that the file is a model this engine can run, then loads it.
    func loadModel(at url: URL, settings: AppSettings) throws {
        if isModelLoaded, loadedPath == url.path { return }
        unload()

        let name = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LlamaRunnerError.missingFile(name)
        }

        let header: GGUFHeader
        do {
            header = try GGUFHeader.read(from: url)
        } catch {
            throw LlamaRunnerError.notGGUF(name)
        }

        if let architecture = header.architecture, !ModelSupport.isSupported(architecture) {
            throw LlamaRunnerError.unsupportedArchitecture(fileName: name, architecture: architecture)
        }

        do {
            let engine = try SwiftLlama(modelPath: url.path,
                                        modelConfiguration: settings.makeConfiguration())
            llama = engine
            loadedPath = url.path
            loadedModelName = name
            isModelLoaded = true
            if settings.jitDebugEnabled {
                lastDiagnostics = Self.diagnostics()
            }
        } catch {
            llama = nil
            loadedPath = nil
            loadedModelName = nil
            isModelLoaded = false
            throw LlamaRunnerError.engineFailed(name)
        }
    }

    func unload() {
        llama = nil
        loadedPath = nil
        loadedModelName = nil
        isModelLoaded = false
    }

    // MARK: - Generation

    /// Streams tokens for a turn. The caller is responsible for handling
    /// `FETCH <url>` commands when web access is enabled.
    ///
    /// llama.cpp decodes the whole prompt in one batch and refuses a prompt larger
    /// than its context, so the prompt is kept inside the window, with room left
    /// for the reply.
    func generateStream(userMessage: String,
                        history: [ChatMessage],
                        settings: AppSettings) async throws -> AsyncThrowingStream<String, Error> {
        guard let llama else {
            throw LlamaRunnerError.noModel
        }

        let context = max(256, settings.contextSize)
        let replyTokens = max(64, min(settings.maxTokens, context / 2))
        // Characters, not tokens: three per token is a safe guess for English, and
        // the slack covers the chat template's own markers.
        let promptCharacters = max(400, (context - replyTokens - 64) * 3)

        var systemPrompt = settings.systemPrompt
        if settings.webAccessEnabled {
            systemPrompt += "\n\n" + ToolParser.instruction(for: settings)
        }
        if systemPrompt.count > promptCharacters / 2 {
            systemPrompt = String(systemPrompt.prefix(promptCharacters / 2))
        }

        var user = userMessage
        let userBudget = max(300, promptCharacters - systemPrompt.count - 64)
        if user.count > userBudget {
            user = String(user.prefix(userBudget))
        }

        let historyBudget = max(0, promptCharacters - systemPrompt.count - user.count - 64)
        let chatHistory = Self.historyPairs(from: history, budgetCharacters: historyBudget)

        let prompt = Prompt(type: settings.template.promptType,
                            systemPrompt: systemPrompt,
                            userMessage: user,
                            history: chatHistory)

        return try await llama.start(for: prompt)
    }

    /// Pairs consecutive user/assistant messages into the engine's history format,
    /// keeping only the newest pairs that fit in `budgetCharacters`.
    static func historyPairs(from messages: [ChatMessage], budgetCharacters: Int = Int.max) -> [Chat] {
        var pairs: [(chat: Chat, cost: Int)] = []
        var pendingUser: String?
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                pendingUser = message.text
            case .assistant:
                if let user = pendingUser {
                    pairs.append((Chat(user: user, bot: message.text), user.count + message.text.count))
                    pendingUser = nil
                }
            case .system:
                continue
            }
        }

        guard budgetCharacters > 0 else { return [] }

        var kept: [(chat: Chat, cost: Int)] = []
        var remaining = budgetCharacters
        for pair in pairs.reversed() {
            if pair.cost > remaining && !kept.isEmpty { break }
            kept.append(pair)
            remaining -= pair.cost
            if remaining <= 0 { break }
        }
        return kept.reversed().map { $0.chat }
    }

    // MARK: - Extended memory debugging

    /// Reports the process's physical memory footprint in bytes.
    static func physicalFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// Tests whether dynamic code execution (JIT) is permitted for this process.
    static func jitStatus() -> JITStatus {
        let pageSize = 4096
        let pointer = mmap(nil, pageSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
        guard pointer != MAP_FAILED else { return .unknown }
        defer { munmap(pointer, pageSize) }
        if mprotect(pointer, pageSize, PROT_READ | PROT_EXEC) == 0 {
            return .available
        }
        return .denied
    }

    /// A human-readable report shown when extended memory debugging is on.
    static func diagnostics() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        var lines: [String] = []
        lines.append("Memory footprint: \(formatter.string(fromByteCount: physicalFootprint()))")
        switch jitStatus() {
        case .available:
            lines.append("JIT: dynamic code execution is permitted")
        case .denied:
            lines.append("JIT: not permitted by iOS (missing dynamic-codesigning entitlement); memory debugging is still active")
        case .unknown:
            lines.append("JIT: could not be determined")
        }
        var limit = rlimit()
        getrlimit(RLIMIT_MEMLOCK, &limit)
        lines.append("Memory-map lock limit: \(limit.rlim_cur == UInt64.max ? "unlimited" : "\(limit.rlim_cur) bytes")")
        lines.append("CPU cores available: \(ProcessInfo.processInfo.processorCount)")
        return lines.joined(separator: "\n")
    }
}
