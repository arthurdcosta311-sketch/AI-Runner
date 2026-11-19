//
//  ChatViewModel.swift
//  AI Runner
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var currentConversationID: UUID?
    @Published private(set) var isGenerating = false
    @Published var showingDrawer = false
    @Published var statusText: String?
    @Published var errorText: String?

    private var generationTask: Task<Void, Never>?
    /// Set when the user taps Stop. The reply keeps draining so the engine is
    /// never interrupted mid-decode: llama.cpp aborts the process if a second
    /// decode starts while one is still running.
    private var stopRequested = false
    private var turnRunner: ChatTurnRunner?
    private var pendingUserText = ""
    private var usedWebInCurrent = false
    private let legacyStorageKey = "chatHistory"
    private let currentKey = "currentConversationID"

    /// The most tool commands one reply may run, so a model can never loop forever.
    private static let maxToolRounds = 8
    /// The longest tool output sent back to the model, in characters.
    private static let maxToolOutput = 12_000

    private static var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chats.json")
    }

    init() {
        load()
    }

    // MARK: - Sending

    func send(_ text: String, runner: LlamaRunner, settings: AppSettings) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }
        guard !runner.isLoadingModel else {
            errorText = "The model is still loading. Give it a few seconds."
            return
        }
        guard runner.isModelLoaded else {
            errorText = "No model loaded. Open the Models tab and load a language model first."
            return
        }

        if currentConversationID == nil {
            let conversation = Conversation(id: UUID(),
                                            title: Self.title(for: trimmed),
                                            messages: [],
                                            usedWeb: false,
                                            updatedAt: Date())
            conversations.insert(conversation, at: 0)
            currentConversationID = conversation.id
        }

        pendingUserText = trimmed
        messages.append(ChatMessage(role: .user, text: trimmed))
        saveCurrent()
        errorText = nil
        statusText = "Thinking…"
        isGenerating = true

        generationTask = Task { [weak self] in
            await self?.runConversation(runner: runner, settings: settings)
        }
    }

    /// Asks the reply to stop. The run keeps draining the engine's stream, so a
    /// new message can never start while llama.cpp is still decoding; the send
    /// button stays disabled until the engine has finished.
    func stop() {
        guard isGenerating else { return }
        stopRequested = true
        turnRunner?.stop()
        statusText = "Stopping…"
    }

    func clearChat() {
        stop()
        messages.removeAll()
        usedWebInCurrent = false
        saveCurrent()
    }

    // MARK: - Conversations drawer

    func select(_ id: UUID) {
        showingDrawer = false
        guard id != currentConversationID else { return }
        stop()
        saveCurrent()
        if let conversation = conversations.first(where: { $0.id == id }) {
            currentConversationID = id
            messages = conversation.messages
            usedWebInCurrent = conversation.usedWeb
        }
        errorText = nil
        statusText = nil
    }

    func newChat() {
        showingDrawer = false
        stop()
        saveCurrent()
        messages = []
        currentConversationID = nil
        usedWebInCurrent = false
        errorText = nil
        statusText = nil
    }

    func delete(_ id: UUID) {
        if id == currentConversationID {
            stop()
            messages = []
            currentConversationID = nil
            usedWebInCurrent = false
        }
        conversations.removeAll { $0.id == id }
        persistAll()
    }

    /// A short title generated from the conversation's first user message.
    static func title(for text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !flattened.isEmpty else { return "New chat" }
        if flattened.count <= 40 { return flattened }
        return String(flattened.prefix(40)) + "…"
    }

    // MARK: - Conversation loop

    /// Generates a reply. When the reply asks for a tool, the app runs it, feeds the
    /// result back to the model and lets it continue, until it answers without a tool.
    private func runConversation(runner: LlamaRunner, settings: AppSettings) async {
        let turn = ChatTurnRunner(runner: runner)
        turnRunner = turn
        defer { turnRunner = nil }

        var toolRounds = 0
        var userMessage = pendingUserText

        while !Task.isCancelled {
            var reply = ""
            let assistant = ChatMessage(role: .assistant, text: "")
            messages.append(assistant)

            do {
                // llama.cpp submits Metal work that iOS aborts if the app is not
                // in the foreground, so never start a reply in the background.
                if UIApplication.shared.applicationState != .active {
                    removeMessage(id: assistant.id)
                    errorText = "The app went to the background. Tap Send to try again."
                    break
                }
                if stopRequested {
                    removeMessage(id: assistant.id)
                    break
                }

                let history = Array(messages.dropLast())
                reply = try await turn.stream(userMessage: userMessage,
                                              history: history,
                                              settings: settings) { partial in
                    updateMessage(id: assistant.id, text: partial)
                }

                if stopRequested {
                    let kept = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    if kept.isEmpty {
                        removeMessage(id: assistant.id)
                    } else {
                        updateMessage(id: assistant.id, text: kept)
                    }
                    break
                }

                if reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    removeMessage(id: assistant.id)
                    errorText = "The model stopped without writing a reply. It may be too large for this phone's memory, or the conversation may no longer fit its context window. Try a smaller model, or start a new chat."
                    break
                }

                let parsed = settings.webAccessEnabled
                    ? ToolParser.parse(reply)
                    : ParsedReply(visibleText: reply.trimmingCharacters(in: .whitespacesAndNewlines), call: nil)
                updateMessage(id: assistant.id, text: parsed.visibleText)

                guard let call = parsed.call, toolRounds < Self.maxToolRounds else { break }

                toolRounds += 1
                usedWebInCurrent = true
                statusText = call.statusLabel
                let output = await ToolExecutor.run(call, settings: settings)
                let done = output.hasPrefix("Error") ? "✕ \(call.name) failed" : "✓ \(call.name) finished"
                let lead = parsed.visibleText.isEmpty ? "" : parsed.visibleText + "\n\n"
                updateMessage(id: assistant.id, text: lead + done)
                userMessage = Self.toolResultPrompt(for: call, output: output)
                statusText = "Thinking…"
            } catch is CancellationError {
                if reply.isEmpty {
                    removeMessage(id: assistant.id)
                }
                break
            } catch {
                errorText = error.localizedDescription
                if reply.isEmpty {
                    removeMessage(id: assistant.id)
                }
                break
            }
        }

        stopRequested = false
        statusText = nil
        isGenerating = false
        saveCurrent()
    }

    /// The message that carries a tool's result back to the model.
    static func toolResultPrompt(for call: ToolCall, output: String) -> String {
        let shown = output.count > maxToolOutput
            ? String(output.prefix(maxToolOutput)) + "\n…(output shortened)"
            : output
        return """
        Result of \(call.name):

        \(shown)

        Continue your answer using this result. Use another tool only if you still need one.
        """
    }

    // MARK: - Message helpers

    private func updateMessage(id: UUID, text: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text = text
        }
    }

    private func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: Self.storageURL),
           let stored = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = stored
        } else if let data = UserDefaults.standard.data(forKey: legacyStorageKey),
                  let old = try? JSONDecoder().decode([ChatMessage].self, from: data),
                  !old.isEmpty {
            // One-time migration from the single-chat storage.
            let title = Self.title(for: old.first(where: { $0.role == .user })?.text ?? "Chat")
            let conversation = Conversation(id: UUID(), title: title, messages: old, usedWeb: false, updatedAt: Date())
            conversations = [conversation]
            currentConversationID = conversation.id
            messages = old
            persistAll()
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        }

        if let idString = UserDefaults.standard.string(forKey: currentKey),
           let id = UUID(uuidString: idString),
           let conversation = conversations.first(where: { $0.id == id }) {
            currentConversationID = id
            messages = conversation.messages
            usedWebInCurrent = conversation.usedWeb
        }
    }

    /// Writes the working messages back into the current conversation, then saves everything.
    private func saveCurrent() {
        if let id = currentConversationID,
           let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].messages = messages
            conversations[index].updatedAt = Date()
            conversations[index].usedWeb = conversations[index].usedWeb || usedWebInCurrent
        }
        persistAll()
    }

    private func persistAll() {
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: Self.storageURL, options: .atomic)
        }
        if let id = currentConversationID {
            UserDefaults.standard.set(id.uuidString, forKey: currentKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentKey)
        }
    }
}
