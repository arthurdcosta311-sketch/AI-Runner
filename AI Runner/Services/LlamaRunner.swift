//
//  LlamaRunner.swift
//  AI Runner
//

import Foundation
import MachO
import SwiftLlama

enum LlamaRunnerError: LocalizedError {
    case noModel

    var errorDescription: String? {
        switch self {
        case .noModel:
            return "No model is loaded. Download or import a GGUF model in the Models tab."
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

    func loadModel(at url: URL, settings: AppSettings) throws {
        if isModelLoaded, loadedPath == url.path { return }
        unload()
        let engine = try SwiftLlama(modelPath: url.path, modelConfiguration: settings.makeConfiguration())
        llama = engine
        loadedPath = url.path
        loadedModelName = url.lastPathComponent
        isModelLoaded = true
        if settings.jitDebugEnabled {
            lastDiagnostics = Self.diagnostics()
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
    func generateStream(userMessage: String,
                        history: [ChatMessage],
                        settings: AppSettings) async throws -> AsyncThrowingStream<String, Error> {
        guard let llama else {
            throw LlamaRunnerError.noModel
        }

        var systemPrompt = settings.systemPrompt
        if settings.webAccessEnabled {
            systemPrompt += "\n\n" + WebTool.instruction
        }

        let chatHistory = Self.historyPairs(from: history)
        let prompt = Prompt(type: settings.template.promptType,
                            systemPrompt: systemPrompt,
                            userMessage: userMessage,
                            history: chatHistory)

        return try await llama.start(for: prompt)
    }

    /// Pairs consecutive user/assistant messages into the engine's history format.
    static func historyPairs(from messages: [ChatMessage]) -> [Chat] {
        var pairs: [Chat] = []
        var pendingUser: String?
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                pendingUser = message.text
            case .assistant:
                if let user = pendingUser {
                    pairs.append(Chat(user: user, bot: message.text))
                    pendingUser = nil
                }
            case .system:
                continue
            }
        }
        return pairs
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