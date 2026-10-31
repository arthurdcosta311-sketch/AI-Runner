//
//  ConversationsDrawerView.swift
//  AI Runner
//

import SwiftUI

/// The conversations drawer: a list of saved chats with a New chat button.
struct ConversationsDrawerView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private var sorted: [Conversation] {
        viewModel.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sorted.isEmpty {
                    ContentUnavailableView("No chats yet",
                                           systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Start a conversation and it will be saved here automatically."))
                } else {
                    List {
                        ForEach(sorted) { conversation in
                            Button {
                                viewModel.select(conversation.id)
                                dismiss()
                            } label: {
                                ConversationRow(conversation: conversation,
                                                isCurrent: conversation.id == viewModel.currentConversationID)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.delete(conversation.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    viewModel.newChat()
                    dismiss()
                } label: {
                    Label("New chat", systemImage: "plus.bubble")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAmber)
                .foregroundStyle(.black)
                .padding()
                .background(.bar)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left")
                .font(.title3)
                .foregroundStyle(.appAmber)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    if conversation.usedWeb {
                        Text("web")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appAmber.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                Text(conversation.messages.last?.text ?? "Empty conversation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.appAmber)
                    .accessibilityLabel("Current conversation")
            }
        }
        .contentShape(Rectangle())
    }
}