//
//  ChatTurnRunner.swift
//  AI Runner
//

import Foundation

/// Runs one model turn the way the ios-local-llm services do: the reply is
/// consumed off the SwiftUI update path, tokens are coalesced into a few
/// redraws per second instead of one per token, and Stop asks the turn to end
/// without cancelling the engine mid-decode.
@MainActor
final class ChatTurnRunner {
    private let runner: LlamaRunner
    private var stopRequested = false
    private(set) var isRunning = false

    /// How often partial text is pushed into the UI. Per-token updates redraw
    /// the whole message list hundreds of times per answer, which is what made
    /// the chat look frozen.
    private let updateInterval: TimeInterval = 0.1

    init(runner: LlamaRunner) {
        self.runner = runner
    }

    /// Asks the turn to stop. The stream keeps being drained so llama.cpp is
    /// never left decoding while the app thinks it is idle; only the visible
    /// updates stop.
    func stop() {
        stopRequested = true
    }

    /// Streams one turn and returns the whole reply text. `onText` receives
    /// the text so far, at most every `updateInterval` seconds.
    func stream(userMessage: String,
                history: [ChatMessage],
                settings: AppSettings,
                onText: @escaping (String) -> Void) async throws -> String {
        guard !isRunning else { throw LlamaRunnerError.busy }
        isRunning = true
        stopRequested = false
        defer { isRunning = false }

        let stream = try await runner.generateStream(userMessage: userMessage,
                                                     history: history,
                                                     settings: settings)
        var full = ""
        var lastUpdate = Date.distantPast
        for try await delta in stream {
            full += delta
            if stopRequested { continue }
            let now = Date()
            if now.timeIntervalSince(lastUpdate) >= updateInterval {
                lastUpdate = now
                onText(full)
            }
        }
        onText(full)
        return full
    }
}
