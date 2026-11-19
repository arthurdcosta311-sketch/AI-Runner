//
//  ChatView.swift
//  AI Runner
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var runner: LlamaRunner
    @ObservedObject var settings: AppSettings
    @StateObject private var viewModel = ChatViewModel()

    @State private var draft = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !runner.isModelLoaded {
                    loadPromptBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                messageList
                statusFooter
                inputBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .animation(.smooth, value: runner.isModelLoaded)
            .animation(.smooth, value: viewModel.statusText)
            .navigationTitle(runner.loadedModelName ?? "AI Runner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showingDrawer) {
                ConversationsDrawerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, runner: runner)
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
                            MessageBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .padding()
                    .animation(.smooth, value: viewModel.messages.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation(.smooth) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
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
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

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
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .background(
                    message.role == .user ? Color.appPurple : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if message.role != .user { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity)
    }
}
