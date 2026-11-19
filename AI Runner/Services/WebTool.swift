//
//  WebTool.swift
//  AI Runner
//

import Foundation

/// Reads web pages as plain text for the model's FETCH command.
enum WebTool {
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

extension HTTPURLResponse {
    /// A response header by name, matched without regard to case.
    func headerValue(_ name: String) -> String? {
        allHeaderFields
            .first { ($0.key as? String)?.caseInsensitiveCompare(name) == .orderedSame }?
            .value as? String
    }
}
