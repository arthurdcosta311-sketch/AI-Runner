//
//  ChatTurnRunner.swift
//  AI Runner
//

import Foundation

/// One model turn, ported from the chat path in ios-local-llm.
///
/// Their services keep three rules that this app's earlier loop broke:
///
///  * The turn is consumed off the main actor, and the decode is started at a
///    priority below the interface's, so long generation cannot starve the
///    screen. Their GGUF engine leans on the GPU for that; this engine is
///    CPU-only, which is why priority is what keeps the app responsive here.
///  * Tokens are buffered and flushed on an interval — the first token straight
///    away, then a few times a second — instead of one UI update per token.
///  * Stop only asks for silence: the stream is drained to the end so llama.cpp
///    is never left decoding while the app believes the engine is idle.
///
/// Deliberately not main-actor bound: `stream` runs on the global executor, and
/// only the text hand-offs hop to the main actor.
final class ChatTurnRunner: @unchecked Sendable {
    private let runner: LlamaRunner
    /// Guards the stop flag and the running latch, both touched from two threads.
    private let lock = NSLock()
    private var stopRequested = false
    private var running = false

    /// How long tokens are collected before the visible text is refreshed, in
    /// the spirit of their StreamingResponseCoordinator buffer interval.
    private let flushInterval: TimeInterval = 0.2
    /// A long burst is shown early instead of waiting for the next tick.
    private let flushCharacters = 400

    init(runner: LlamaRunner) {
        self.runner = runner
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// Asks the turn to stop writing. Safe from any thread.
    func stop() {
        lock.lock()
        stopRequested = true
        lock.unlock()
    }

    /// Runs one turn and returns the whole reply. `onUpdate` receives the text
    /// so far on the main actor: immediately for the first token, then at most
    /// every `flushInterval` seconds.
    @discardableResult
    func stream(userMessage: String,
                history: [ChatMessage],
                settings: AppSettings,
                onUpdate: @MainActor @escaping (String) -> Void) async throws -> String {
        lock.lock()
        let alreadyRunning = running
        running = true
        stopRequested = false
        lock.unlock()

        guard !alreadyRunning else { throw LlamaRunnerError.busy }

        let engine = runner
        defer {
            lock.lock()
            running = false
            lock.unlock()
            // Clears the engine's busy latch on the main actor, where the
            // published state lives.
            Task { @MainActor in engine.endGeneration() }
        }

        let stream = try await runner.generateStream(userMessage: userMessage,
                                                     history: history,
                                                     settings: settings)

        var full = ""
        var pending = ""
        var sentFirst = false
        var lastFlush = Date.distantPast

        for try await delta in stream {
            full += delta
            pending += delta

            guard !isStopped else { continue }

            let now = Date()
            let due = !sentFirst
                || pending.count >= flushCharacters
                || now.timeIntervalSince(lastFlush) >= flushInterval
            guard due else { continue }

            sentFirst = true
            pending = ""
            lastFlush = now
            let text = full
            await MainActor.run { onUpdate(text) }
            // Gives the interface a turn between flushes rather than queueing
            // the next token behind the redraw.
            await Task.yield()
        }

        let final = full
        await MainActor.run { onUpdate(final) }
        return full
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }
}
