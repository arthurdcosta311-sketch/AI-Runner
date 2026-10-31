//
//  ChatViewModel.swift
//  AI Runner
//

import Foundation
import SwiftUI

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
    private var pendingUserText = ""
    private var usedWebInCurrent = false
    private let legacyStorageKey = "chatHistory"
    private let currentKey = "currentConversationID"

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
        guard runner.isModelLoaded else {
            errorText = "No model loaded. Open the Models tab and load a GGUF model first."
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

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        statusText = nil
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

    private func runConversation(runner: LlamaRunner, settings: AppSettings) async {
        var fetchCount = 0
        var lastUserMessage = pendingUserText

        while !Task.isCancelled {
            var reply = ""
            let assistant = ChatMessage(role: .assistant, text: "")
            messages.append(assistant)

            do {
                let history = Array(messages.dropLast())
                let stream = try await runner.generateStream(userMessage: lastUserMessage,
                                                             history: history,
                                                             settings: settings)
                for try await delta in stream {
                    reply += delta
                    updateMessage(id: assistant.id, text: reply)
                }

                // If the model asked for a web page, fetch it and let it continue.
                if settings.webAccessEnabled, fetchCount < 2, let url = WebTool.extractCommand(from: reply) {
                    statusText = "Fetching \(url.host ?? url.absoluteString)…"
                    fetchCount += 1
                    usedWebInCurrent = true
                    let clean = WebTool.strippingCommand(from: reply)
                    updateMessage(id: assistant.id, text: clean)
                    do {
                        let page = try await WebTool.fetchText(from: url)
                        updateMessage(id: assistant.id, text: clean + "\n\n✓ Fetched page")
                        lastUserMessage = """
                        Web page content from \(url.absoluteString):

                        \(page)

                        Using the page content above, continue and finish your answer.
                        """
                        continue
                    } catch {
                        updateMessage(id: assistant.id, text: clean + "\n\n(Failed to fetch the page: \(error.localizedDescription))")
                        break
                    }
                }

                if settings.webAccessEnabled {
                    let clean = WebTool.strippingCommand(from: reply)
                    updateMessage(id: assistant.id, text: clean.isEmpty ? reply : clean)
                }
                break
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

        statusText = nil
        isGenerating = false
        saveCurrent()
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