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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !runner.isModelLoaded {
                    loadPromptBanner
                }
                messageList
                statusFooter
                inputBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("AI Runner")
            .sheet(isPresented: $viewModel.showingDrawer) {
                ConversationsDrawerView(viewModel: viewModel)
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
                        Image(systemName: settings.webAccessEnabled ? "globe" : "globe.slash")
                    }
                    .tint(settings.webAccessEnabled ? .appAmber : .secondary)
                    .accessibilityLabel("Toggle web access")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.clearChat()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear chat")
                }
            }
        }
    }

    // MARK: - Sections

    private var loadPromptBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.title2)
                .foregroundStyle(.appAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("No model loaded")
                    .font(.subheadline.weight(.semibold))
                Text("Open the Models tab and load a GGUF model to start chatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages) { _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
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
        }
        if let error = viewModel.errorText {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 18))

            Button {
                if viewModel.isGenerating {
                    viewModel.stop()
                } else {
                    viewModel.send(draft, runner: runner, settings: settings)
                    draft = ""
                }
            } label: {
                Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.appAmber)
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
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text.isEmpty ? "…" : message.text)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            .background(
                message.role == .user
                    ? AnyShapeStyle(.appAmber.opacity(0.85))
                    : AnyShapeStyle(.background.secondary),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(message.role == .user ? .black : .primary)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}