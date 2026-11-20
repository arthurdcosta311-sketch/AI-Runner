//
//  LlamaRunner.swift
//  AI Runner
//

import Foundation
import MachO
import os
import SwiftLlama

enum LlamaRunnerError: LocalizedError {
    case noModel
    case missingFile(String)
    case notGGUF(String)
    case unsupportedArchitecture(fileName: String, architecture: String)
    case engineFailed(String)
    case busy
    case outOfMemory(fileName: String, neededBytes: Int64, availableBytes: Int64)
    case lowMemory(availableBytes: Int64)

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
        case .busy:
            return "The model is still working on the previous answer. Wait for it to finish, then try again."
        case .outOfMemory(let fileName, let neededBytes, let availableBytes):
            let needed = ByteCountFormatter.string(fromByteCount: neededBytes, countStyle: .memory)
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .memory)
            return "\(fileName) needs about \(needed) of memory to load and run, but only \(available) is free for this app right now. Close other apps, or choose a smaller model."
        case .lowMemory(let availableBytes):
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .memory)
            return "Only \(available) of memory is free, too little to run the model. Close other apps and try again."
        }
    }
}

enum JITStatus {
    case available
    case denied
    case unknown
}

/// Runs a local GGUF model through llama.cpp.
///
/// Main-actor bound because every published value here drives SwiftUI: setting
/// `@Published` state from a background thread is what makes SwiftUI updates
/// arrive out of order, and the heavy work (loading, decoding) is pushed off to
/// detached tasks instead of the state being pushed off the actor.
@MainActor
final class LlamaRunner: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var isLoadingModel = false
    @Published private(set) var loadingModelName: String?
    @Published private(set) var loadedModelName: String?
    @Published private(set) var lastDiagnostics: String = ""
    /// True while a reply is being generated, so nothing else touches the engine.
    @Published var isGenerating = false

    private var llama: SwiftLlama?
    private var loadedPath: String?

    /// Live memory the process can still allocate, in bytes (0 when unknown).
    static var availableMemory: Int64 {
        Int64(os_proc_available_memory())
    }

    // MARK: - Model lifecycle

    /// Checks that the file is a model this engine can run, then loads it.
    ///
    /// llama.cpp maps the weights and builds the context in one long call, so it
    /// runs on a background task: the app stays responsive and shows progress
    /// instead of freezing for the seconds a multi-gigabyte model takes to load.
    func loadModel(at url: URL, settings: AppSettings) async throws {
        if isModelLoaded, loadedPath == url.path { return }
        if isLoadingModel || isGenerating { throw LlamaRunnerError.busy }

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

        // Refuse a load that would be killed for memory, the way ios-local-llm's
        // MemoryAdvisor does: weights, the KV cache and Metal buffers need well
        // over the file's size, plus headroom for the app itself.
        let fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        if fileSize > 0 {
            let needed = Int64(Double(fileSize) * 1.3) + 500_000_000
            let available = Self.availableMemory
            if available > 0, available < needed {
                throw LlamaRunnerError.outOfMemory(fileName: name,
                                                   neededBytes: needed,
                                                   availableBytes: available)
            }
        }

        // Release the previous engine first so its weights are not held while
        // the new ones are mapped in.
        unload()
        isLoadingModel = true
        loadingModelName = name
        defer {
            isLoadingModel = false
            loadingModelName = nil
        }

        let path = url.path
        let configuration = settings.makeConfiguration()
        do {
            let engine = try await Task.detached(priority: .userInitiated) {
                try SwiftLlama(modelPath: path, modelConfiguration: configuration)
            }.value
            llama = engine
            loadedPath = path
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
        guard !isGenerating else {
            throw LlamaRunnerError.busy
        }

        // Running the model needs room for the compute graph, so a nearly full
        // process is better refused than left to be killed mid-answer.
        let available = Self.availableMemory
        if available > 0, available < 150_000_000 {
            throw LlamaRunnerError.lowMemory(availableBytes: available)
        }

        // SwiftLlama tokenizes the whole prompt and runs one synchronous decode
        // over it before the first token exists, and its model wrapper counts
        // prompt and reply together against a hard 1024-token budget. So the
        // prompt is capped in tokens — long enough for the system prompt, the
        // tools instructions and a little history, short enough that the model
        // starts writing in seconds — and leaves the rest of the budget for the
        // reply. Their bridge does the same arithmetic against its own context.
        let configuration = settings.makeConfiguration()
        let context = configuration.nCTX
        let totalBudget = min(configuration.maxTokenCount, 1024)
        let promptTokenBudget = max(160, min(384, context - 256, totalBudget - 192))
        // Characters per token: about 3.2 for English, and the slack covers the
        // chat template's own markers.
        let promptCharacters = Int(Double(promptTokenBudget) * 3.2)

        var systemPrompt = settings.systemPrompt
        if settings.webAccessEnabled {
            systemPrompt += "\n\n" + ToolParser.instruction(for: settings)
        }
        // The system prompt carries the tools list, so it is cut at a line
        // boundary rather than mid-sentence when the budget is tight.
        let systemBudget = Int(Double(promptCharacters) * 0.65)
        if systemPrompt.count > systemBudget {
            systemPrompt = Self.truncated(systemPrompt, to: systemBudget)
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

        // Keep the engine latched as busy for as long as the reply streams, so a
        // second send can never start a decode while llama.cpp is still working:
        // two concurrent decodes on one context abort the process. The latch is
        // cleared by `endGeneration()` when the turn's stream has been drained.
        isGenerating = true
        do {
            let engine = llama
            // ios-local-llm's GGUF path puts the whole decode on the GPU, which
            // leaves the CPU free for the interface. This engine is CPU-only
            // (SwiftLlama never raises n_gpu_layers), so the decode is started at
            // utility priority instead: its threads give way to the main thread
            // and the app keeps responding while the reply is written. The inner
            // decode task inherits this priority from the task that starts it.
            let stream = try await Task.detached(priority: .utility) { () throws
                -> AsyncThrowingStream<String, Error> in
                let tokens: AsyncThrowingStream<String, Error> = try await engine.start(for: prompt)
                return tokens
            }.value
            return stream
        } catch {
            isGenerating = false
            throw error
        }
    }

    /// Clears the busy latch once a turn has finished or been abandoned.
    func endGeneration() {
        isGenerating = false
    }

    /// Cuts text to at most `limit` characters, preferring the last whole line so
    /// an instruction is never left half-written.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let lastNewline = head.lastIndex(of: "\n"), head.distance(from: head.startIndex, to: lastNewline) > limit / 2 {
            return String(head[head.startIndex..<lastNewline])
        }
        return head
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
