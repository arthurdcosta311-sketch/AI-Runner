//
//  BrowserView.swift
//  AI Runner
//

import SwiftUI
import WebKit

/// The Browser tab: the Focus search engine, and pages opened in a web view.
/// Nothing is saved: pages use a non-persistent data store, so no cookies or history are kept.
struct BrowserView: View {
    @State private var query = ""
    @State private var results: [FocusResult] = []
    @State private var page: URL?
    @State private var isSearching = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if let page {
                    WebPage(url: page)
                } else {
                    resultsList
                }
            }
            .navigationTitle(page?.host ?? "Browser")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search Focus or enter a website")
            .onSubmit(of: .search) { submit() }
            .toolbar {
                if page != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            page = nil
                        } label: {
                            Label("Results", systemImage: "list.bullet")
                        }
                    }
                }
            }
            .animation(.smooth, value: page)
            .animation(.smooth, value: results.count)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isSearching {
            ProgressView("Searching Focus…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView {
                Label("Focus", systemImage: "magnifyingglass")
            } description: {
                Text(errorText ?? "Search the web with the Focus engine, or type a website address. Nothing is saved: no cookies and no history.")
            }
        } else {
            List(results) { result in
                Button {
                    page = result.url
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.headline)
                            .foregroundStyle(.appPurple)
                            .lineLimit(2)
                        Text(result.url.host ?? result.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !result.snippet.isEmpty {
                            Text(result.snippet)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let url = Self.addressURL(for: text) {
            page = url
            return
        }
        Task { await search(text) }
    }

    private func search(_ text: String) async {
        isSearching = true
        errorText = nil
        defer { isSearching = false }
        do {
            results = try await FocusEngine.search(text)
            page = nil
            if results.isEmpty {
                errorText = "No results. Try different words."
            }
        } catch {
            results = []
            errorText = "The search failed. Check your connection and try again."
        }
    }

    /// The address to open when the text is a web address ("example.com/path" or "https://…"), otherwise nil.
    static func addressURL(for text: String) -> URL? {
        let lowered = text.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: text)
        }
        guard !text.contains(" "), text.contains("."), !text.hasPrefix("."), !text.hasSuffix(".") else {
            return nil
        }
        let labels = text.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else {
            return nil
        }
        return URL(string: "https://" + text)
    }
}

/// A page in a web view. A new address loads when the view receives it.
struct WebPage: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loaded: URL?
    }
}
