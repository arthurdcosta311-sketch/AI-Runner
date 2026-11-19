//
//  MCPClient.swift
//  AI Runner
//

import Foundation

enum MCPError: LocalizedError {
    case http(Int, String)
    case badResponse
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "The MCP server returned status \(code). \(body)"
        case .badResponse:
            return "The MCP server sent a reply that could not be read."
        case .rpc(let message):
            return "MCP error: \(message)"
        }
    }
}

/// A small client for MCP servers over Streamable HTTP. Each call opens a session,
/// sends one request and returns the result as JSON text.
enum MCPClient {
    static func call(_ server: MCPServer, token: String?, method: String, params: [String: Any]) async throws -> String {
        guard let url = server.endpoint else { throw URLError(.badURL) }

        let handshake = try await post(url, token: token, session: nil, body: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-03-26",
                "capabilities": [String: Any](),
                "clientInfo": ["name": "AI Runner", "version": "1.0"]
            ]
        ])
        let session = handshake.response.headerValue("Mcp-Session-Id")

        _ = try? await post(url, token: token, session: session, body: [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        ])

        let reply = try await post(url, token: token, session: session, body: [
            "jsonrpc": "2.0",
            "id": 2,
            "method": method,
            "params": params
        ])
        let result = try parseResult(reply.data, contentType: reply.response.headerValue("Content-Type"))
        let pretty = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .fragmentsAllowed])
        return String(decoding: pretty, as: UTF8.self)
    }

    private static func post(_ url: URL, token: String?, session: String?, body: [String: Any]) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let session {
            request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MCPError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPError.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (data, http)
    }

    /// Reads the JSON-RPC reply, which is plain JSON or a server-sent event stream.
    private static func parseResult(_ data: Data, contentType: String?) throws -> Any {
        var payload = data
        if (contentType ?? "").contains("text/event-stream") {
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            let events = lines
                .filter { $0.hasPrefix("data:") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            guard let last = events.last(where: { !$0.isEmpty }) else { throw MCPError.badResponse }
            payload = Data(last.utf8)
        }
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw MCPError.badResponse
        }
        if let error = object["error"] as? [String: Any] {
            throw MCPError.rpc(error["message"] as? String ?? "unknown error")
        }
        return object["result"] ?? [String: Any]()
    }
}
