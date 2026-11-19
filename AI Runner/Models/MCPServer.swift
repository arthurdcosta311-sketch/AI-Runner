//
//  MCPServer.swift
//  AI Runner
//

import Foundation

/// A remote MCP server the model can call with `MCP <name> <tool> <json>`.
/// Its optional bearer token is kept in the Keychain under `tokenKey`.
struct MCPServer: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String

    var tokenKey: String { "MCP_TOKEN_\(id.uuidString)" }

    var token: String? { ApiKeyManager.shared.get(key: tokenKey) }

    var endpoint: URL? { URL(string: url) }
}
