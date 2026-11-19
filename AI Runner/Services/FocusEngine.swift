//
//  FocusEngine.swift
//  AI Runner
//

import Foundation

/// One result from the Focus search engine.
struct FocusResult: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let snippet: String
}

/// The Focus search engine the models use. It is the engine Focus Lite uses:
/// web results from DuckDuckGo's lightweight HTML endpoint, parsed into titles,
/// links and snippets. Nothing is stored: no cookies, no history.
enum FocusEngine {
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func search(_ query: String, offset: Int = 0) async throws -> [FocusResult] {
        var components = URLComponents(string: "https://lite.duckduckgo.com/lite/")
        var items = [URLQueryItem(name: "q", value: query)]
        if offset > 0 { items.append(URLQueryItem(name: "s", value: String(offset))) }
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Pulls title, link and snippet rows out of the results page.
    static func parse(_ html: String) -> [FocusResult] {
        let anchorPattern = /<a\s([^>]*)>([\s\S]*?)<\/a>/
        let hrefPattern = /href\s*=\s*["']([^"']+)["']/
        let snippetPattern = /<td[^>]*class\s*=\s*['"]result-snippet['"][^>]*>([\s\S]*?)<\/td>/

        // Title anchors carry the result-link class. Each snippet belongs to the
        // title anchor that comes before it.
        var anchors: [(offset: String.Index, attrs: Substring, inner: Substring)] = []
        for match in html.matches(of: anchorPattern) where match.output.1.contains("result-link") {
            anchors.append((match.range.lowerBound, match.output.1, match.output.2))
        }
        let snippets: [(offset: String.Index, text: Substring)] = html.matches(of: snippetPattern).map { match in
            (match.range.lowerBound, match.output.1)
        }

        var results: [FocusResult] = []
        var seen = Set<String>()
        for (index, anchor) in anchors.enumerated() {
            let windowEnd = index + 1 < anchors.count ? anchors[index + 1].offset : html.endIndex
            let snippet = snippets.first { $0.offset > anchor.offset && $0.offset < windowEnd }
                .map { decodeHTML(String($0.text)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

            guard let hrefMatch = anchor.attrs.firstMatch(of: hrefPattern) else { continue }
            let href = String(hrefMatch.1)
            let lowered = href.lowercased()
            // Sponsored entries route through ad trackers, so they are not results.
            guard !lowered.contains("duckduckgo.com/y.js"),
                  !lowered.contains("ad_provider"),
                  !lowered.contains("ad_domain"),
                  let url = resultURL(from: href) else { continue }

            let title = decodeHTML(String(anchor.inner)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { continue }
            results.append(FocusResult(title: title, url: url, snippet: snippet))
            if results.count >= 30 { break }
        }
        return results
    }

    /// Unwraps DuckDuckGo's redirect links and keeps only plain http(s) targets.
    private static func resultURL(from href: String) -> URL? {
        var target = href
        if target.hasPrefix("//") { target = "https:" + target }
        if let components = URLComponents(string: target),
           components.host?.hasSuffix("duckduckgo.com") == true,
           let redirected = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            target = redirected
        }
        guard let url = URL(string: target), let scheme = url.scheme, scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// Strips tags and resolves the common HTML entities.
    private static func decodeHTML(_ text: String) -> String {
        var string = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                        ("&#x27;", "'"), ("&#39;", "'"), ("&nbsp;", " ")]
        for (entity, replacement) in entities {
            string = string.replacingOccurrences(of: entity, with: replacement)
        }
        return string
    }
}
