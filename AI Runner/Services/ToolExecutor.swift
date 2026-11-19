//
//  ToolExecutor.swift
//  AI Runner
//

import Foundation

/// Carries out the commands a model asks for. Each one returns the text the model reads back.
enum ToolExecutor {
    static func run(_ call: ToolCall, settings: AppSettings) async -> String {
        switch call {
        case .fetch(let url):
            do {
                let text = try await WebTool.fetchText(from: url)
                return text.isEmpty ? "The page had no readable text." : text
            } catch {
                return "Error: could not fetch \(url.absoluteString): \(error.localizedDescription)"
            }

        case .search(let query):
            do {
                let results = try await FocusEngine.search(query)
                guard !results.isEmpty else { return "No results for \(query)." }
                return results.prefix(10).enumerated().map { index, result in
                    "\(index + 1). \(result.title)\n\(result.url.absoluteString)\n\(result.snippet)"
                }.joined(separator: "\n\n")
            } catch {
                return "Error: search failed: \(error.localizedDescription)"
            }

        case .curl(let method, let url):
            return await send(method: method, url: url, headers: [:])

        case .github(let path):
            guard let token = ApiKeyManager.shared.get(key: "GITHUB_TOKEN") else {
                return "Error: no GitHub token is saved. Ask the user to add one in Settings, then Integrations."
            }
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            guard let url = URL(string: "https://api.github.com/" + relative) else {
                return "Error: \(path) is not a valid GitHub API path."
            }
            return await send(method: "GET", url: url, headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28"
            ])

        case .mcp(let serverName, let tool, let arguments):
            guard let server = settings.mcpServers.first(where: { $0.name.caseInsensitiveCompare(serverName) == .orderedSame }) else {
                let known = settings.mcpServers.map(\.name).joined(separator: ", ")
                return "Error: no MCP server named \(serverName). Connected servers: \(known.isEmpty ? "none" : known)."
            }
            do {
                if tool == "tools/list" {
                    return try await MCPClient.call(server, token: server.token, method: "tools/list", params: [:])
                }
                let object = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
                return try await MCPClient.call(server, token: server.token, method: "tools/call",
                                                params: ["name": tool, "arguments": object])
            } catch {
                return "Error: \(error.localizedDescription)"
            }

        case .javascript(let code):
            return await ScriptRunner.javaScript(code)

        case .lua(let code):
            return await ScriptRunner.lua(code)
        }
    }

    /// One HTTP request. Returns the status and the body as text.
    static func send(method: String, url: URL, headers: [String: String]) async -> String {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return "HTTP \(status)\n\n" + String(decoding: data, as: UTF8.self)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
