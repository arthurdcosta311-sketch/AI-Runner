//
//  Conversation.swift
//  AI Runner
//

import Foundation

/// A saved chat conversation.
struct Conversation: Identifiable, Codable {
    var id: UUID
    var title: String
    var messages: [ChatMessage]
    var usedWeb: Bool
    var updatedAt: Date
}