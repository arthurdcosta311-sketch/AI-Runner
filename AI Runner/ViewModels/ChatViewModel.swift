//
//  ChatViewModel.swift
//  AI Runner
//

import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isGenerating = false
    @Published var statusText: String?
    @Published var errorText: String?

    private var generationTask: Task<Void, Never>?
    private var pendingUserText = ""
    private let storageKey = "chatHistory"

    init() {
        loadMessages()
    }

    // MARK: - Sending

    func send(_ text: String, runner: LlamaRunner, settings: AppSettings) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }
        guard runner.isModelLoaded else {
            errorText = "No model loaded. Open the Models tab and load a GGUF model first."
            return
        }

        pendingUserText = trimmed
        messages.append(ChatMessage(role: .user, text: trimmed))
        saveMessages()
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
        saveMessages()
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
        saveMessages()
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

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        messages = (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    private func saveMessages() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}