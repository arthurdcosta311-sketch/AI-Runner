//
//  WebTool.swift
//  AI Runner
//

import Foundation

/// Lets a local model read web pages: the model can ask for a page by
/// emitting a `FETCH <url>` line, which the app detects, downloads,
/// and feeds back as context.
enum WebTool {
    static let commandPrefix = "FETCH"
    static let instruction = """
    You have web access. When you need current information or a specific web page, \
    reply with a single line in the form `FETCH https://example.com/page`. \
    The app will download the page and show it to you; then continue your answer using it. \
    Only use FETCH when you actually need the page.
    """

    /// Finds the first `FETCH <url>` command in a model response.
    static func extractCommand(from text: String) -> URL? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix(commandPrefix) else { continue }
            let candidate = trimmed.dropFirst(commandPrefix.count)
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "`", with: "")
            if let url = URL(string: candidate), url.scheme == "http" || url.scheme == "https" {
                return url
            }
        }
        return nil
    }

    /// Removes the FETCH command (and anything after it) from the visible reply.
    static func strippingCommand(from text: String) -> String {
        guard let range = text.range(of: "\n\(commandPrefix)", options: .caseInsensitive) ?? text.range(of: commandPrefix, options: .caseInsensitive) else {
            return text
        }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downloads a web page and returns readable plain text.
    static func fetchText(from url: URL, maxCharacters: Int = 12_000) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        var encoding = String.Encoding.utf8
        if let name = http.textEncodingName {
            let iana = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if iana != kCFStringEncodingInvalidId {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(iana))
            }
        }
        let html = String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? ""
        return String(readableText(fromHTML: html).prefix(maxCharacters))
    }

    /// Crude HTML-to-text conversion: drops scripts, styles and tags.
    static func readableText(fromHTML html: String) -> String {
        let mutable = NSMutableString(string: html)

        let scriptStyle = try? NSRegularExpression(pattern: "(?is)<(script|style|noscript)[^>]*>.*?</\\1>|<head[^>]*>.*?</head>")
        scriptStyle?.replaceMatches(in: mutable, range: NSRange(location: 0, length: mutable.length), withTemplate: " ")

        let tags = try? NSRegularExpression(pattern: "<[^>]+>")
        tags?.replaceMatches(in: mutable, range: NSRange(location: 0, length: mutable.length), withTemplate: " ")

        var text = mutable as String
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}