//
//  ToolCall.swift
//  AI Runner
//

import Foundation

/// A command the model asked the app to run.
enum ToolCall: Equatable {
    case fetch(URL)
    case search(String)
    case curl(method: String, url: URL)
    case github(path: String)
    case mcp(server: String, tool: String, arguments: String)
    case javascript(String)
    case lua(String)

    /// The command's name, as the model writes it.
    var name: String {
        switch self {
        case .fetch: return "FETCH"
        case .search: return "SEARCH"
        case .curl: return "CURL"
        case .github: return "GITHUB"
        case .mcp: return "MCP"
        case .javascript: return "RUN JS"
        case .lua: return "RUN LUA"
        }
    }

    /// What the chat shows while the command runs.
    var statusLabel: String {
        switch self {
        case .fetch(let url): return "Reading \(url.host ?? url.absoluteString)…"
        case .search(let query): return "Searching for “\(query)”…"
        case .curl(_, let url): return "Requesting \(url.host ?? url.absoluteString)…"
        case .github(let path): return "Calling GitHub \(path)…"
        case .mcp(let server, let tool, _): return "Calling \(tool) on \(server)…"
        case .javascript: return "Running JavaScript…"
        case .lua: return "Running Lua…"
        }
    }
}

/// A model reply split into the text to show and the command to run, if any.
struct ParsedReply {
    /// The reply with the command and everything after it removed.
    let visibleText: String
    let call: ToolCall?
}

/// Reads tool commands out of a model's reply. A command is an uppercase keyword
/// at the start of a line (FETCH, SEARCH, CURL, GITHUB, MCP), or `RUN JS` or
/// `RUN LUA` followed by a fenced code block. Lines inside other code blocks are ignored.
enum ToolParser {
    /// The instructions that teach the model its tools. Sent with every message when tools are on.
    static func instruction(for settings: AppSettings) -> String {
        var lines = [
            "You have tools. To use one, write exactly one command on its own line and stop. The app runs it and sends you the result, then you continue your answer from that result. Use a tool only when you need it, and never invent a tool result.",
            "FETCH <url>: read a web page as text.",
            "SEARCH <query>: search the web with the Focus search engine. You get titles, links and snippets.",
            "CURL [GET|POST|HEAD] <url>: make an HTTP request and see the status and body.",
            "RUN JS, on the line after it a ```js code block: run JavaScript on the phone and get what console.log prints.",
            "RUN LUA, on the line after it a ```lua code block: run Lua on the phone and get what print prints.",
        ]
        if settings.hasGitHubToken {
            lines.append("GITHUB <api path>: call the GitHub REST API with the user's token, for example GITHUB repos/apple/swift/issues.")
        }
        if !settings.mcpServers.isEmpty {
            let names = settings.mcpServers.map(\.name).joined(separator: ", ")
            lines.append("MCP <server> <tool> <json arguments>: call a tool on a connected MCP server. Connected servers: \(names). Use MCP <server> list to see a server's tools.")
        }
        return lines.joined(separator: "\n")
    }

    static func parse(_ text: String) -> ParsedReply {
        let lines = text.components(separatedBy: "\n")
        var inFence = false

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard let keyword = parts.first, keyword == keyword.uppercased(),
                  let call = command(keyword, rest: parts.count > 1 ? parts[1] : "", lines: lines, index: index) else {
                continue
            }
            let visible = lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedReply(visibleText: visible, call: call)
        }
        return ParsedReply(visibleText: text.trimmingCharacters(in: .whitespacesAndNewlines), call: nil)
    }

    private static func command(_ keyword: String, rest: String, lines: [String], index: Int) -> ToolCall? {
        let argument = rest.trimmingCharacters(in: .whitespaces)
        switch keyword {
        case "FETCH":
            guard let url = httpURL(argument) else { return nil }
            return ToolCall.fetch(url)
        case "SEARCH":
            return argument.isEmpty ? nil : ToolCall.search(argument)
        case "CURL":
            let pieces = argument.split(separator: " ", maxSplits: 1).map(String.init)
            let methods = ["GET", "POST", "HEAD"]
            if pieces.count == 2, methods.contains(pieces[0].uppercased()), let target = httpURL(pieces[1]) {
                return ToolCall.curl(method: pieces[0].uppercased(), url: target)
            }
            guard let url = httpURL(argument) else { return nil }
            return ToolCall.curl(method: "GET", url: url)
        case "GITHUB":
            return argument.isEmpty ? nil : ToolCall.github(path: argument)
        case "MCP":
            let pieces = argument.split(separator: " ", maxSplits: 2).map(String.init)
            guard pieces.count >= 2 else { return nil }
            let tool = pieces[1] == "list" ? "tools/list" : pieces[1]
            let arguments = pieces.count > 2 ? pieces[2] : "{}"
            return ToolCall.mcp(server: pieces[0], tool: tool, arguments: arguments)
        case "RUN":
            guard let code = fencedBlock(in: lines, after: index) else { return nil }
            switch argument.lowercased() {
            case "js", "javascript": return ToolCall.javascript(code)
            case "lua": return ToolCall.lua(code)
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func httpURL(_ text: String) -> URL? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "`<> "))
        guard let url = URL(string: cleaned), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// The code inside the first fenced block after the given line.
    private static func fencedBlock(in lines: [String], after index: Int) -> String? {
        var code: [String]?
        for line in lines[(index + 1)...] {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let collected = code { return collected.joined(separator: "\n") }
                code = []
            } else if code != nil {
                code?.append(line)
            }
        }
        return nil
    }
}
