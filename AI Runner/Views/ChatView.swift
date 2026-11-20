//
//  ChatView.swift
//  AI Runner
//

import Combine
import SwiftUI
import UIKit

struct ChatView: View {
    @ObservedObject var runner: LlamaRunner
    @ObservedObject var settings: AppSettings
    @StateObject private var viewModel = ChatViewModel()

    @State private var draft = ""
    @State private var showingSettings = false
    @State private var showingBrowser = false
    @FocusState private var inputFocused: Bool
    @State private var keyboardVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if runner.isLoadingModel {
                    loadingBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if !runner.isModelLoaded {
                    loadPromptBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                messageList
                statusFooter
                inputBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .animation(.smooth, value: runner.isModelLoaded)
            .animation(.smooth, value: runner.isLoadingModel)
            .animation(.smooth, value: viewModel.statusText)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.smooth(duration: 0.2)) { keyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.smooth(duration: 0.2)) { keyboardVisible = false }
            }
            .hideKeyboardToolbar()
            .navigationTitle(runner.loadedModelName ?? "AI Runner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showingDrawer) {
                ConversationsDrawerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, runner: runner)
            }
            .sheet(isPresented: $showingBrowser) {
                BrowserView(showsDoneButton: true)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        viewModel.showingDrawer = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("Conversations")

                    Button {
                        settings.webAccessEnabled.toggle()
                    } label: {
                        Image(systemName: settings.webAccessEnabled ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                    }
                    .tint(settings.webAccessEnabled ? .appPurple : .secondary)
                    .accessibilityLabel("Tools")

                    Button {
                        showingBrowser = true
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel("Browser")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.clearChat()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear chat")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    // MARK: - Sections

    private var loadingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.appPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loading \(runner.loadingModelName ?? "model")")
                    .font(.subheadline.weight(.semibold))
                Text("The app stays usable while the weights load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var loadPromptBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.title2)
                .foregroundStyle(.appPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text("No model loaded")
                    .font(.subheadline.weight(.semibold))
                Text("Open Models, download a language model and tap Load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var messageList: some View {
        if viewModel.messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message,
                                          isStreaming: viewModel.isGenerating && message.id == viewModel.messages.last?.id)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                // Follow the newest text without animating: an animated scroll on
                // every update kept restarting its own animation, which is what
                // stalled the screen while a reply streamed.
                .onChange(of: viewModel.messages) { _, _ in
                    guard let last = viewModel.messages.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(runner.isModelLoaded ? "Ask anything" : "No model loaded",
                  systemImage: runner.isModelLoaded ? "sparkles" : "cube.transparent")
        } description: {
            Text(runner.isModelLoaded
                 ? "Tools are \(settings.webAccessEnabled ? "on" : "off"). The model can read pages, search with Focus, run JavaScript and Lua, call GitHub and use MCP servers."
                 : "Open Models and download a language model to start chatting.")
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let status = viewModel.statusText {
            HStack(spacing: 8) {
                ProgressView()
                Text(viewModel.elapsedSeconds > 0 ? "\(status) \(viewModel.elapsedSeconds)s" : status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        if let error = viewModel.errorText {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
                .transition(.opacity)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if keyboardVisible {
                Button {
                    hideKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(.appPurple)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel("Hide keyboard")
            }

            Button {
                if viewModel.isGenerating {
                    viewModel.stop()
                } else {
                    viewModel.send(draft, runner: runner, settings: settings)
                    draft = ""
                }
            } label: {
                Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.appPurple)
            }
            .disabled(!viewModel.isGenerating && draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(viewModel.isGenerating ? "Stop" : "Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.smooth(duration: 0.2), value: keyboardVisible)
    }

    private func hideKeyboard() {
        inputFocused = false
        dismissKeyboard()
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    /// True for the message currently being written by the model.
    let isStreaming: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            bubble
            if message.role != .user { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bubble: some View {
        let content = Text(message.text.isEmpty ? "…" : message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            .background(
                message.role == .user ? Color.appPurple : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )

        // Selecting text in a bubble that changes ten times a second makes every
        // update re-lay out a selection view, so only finished messages can be
        // selected.
        if isStreaming {
            content.textSelection(.disabled)
        } else {
            content.textSelection(.enabled)
        }
    }
}
