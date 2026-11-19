//
//  DownloadsSection.swift
//  AI Runner
//

import SwiftUI

/// The list of downloads in progress and recently finished. Shows nothing when there are none.
struct DownloadsSection: View {
    @ObservedObject var manager = DownloadManager.shared

    var body: some View {
        if !manager.downloads.isEmpty {
            Section {
                ForEach(manager.downloads) { download in
                    DownloadRow(download: download)
                }
                Button("Clear finished") {
                    manager.clearFinished()
                }
                .foregroundStyle(.secondary)
            } header: {
                Text("Downloads")
            }
            .animation(.smooth, value: manager.downloads.count)
        }
    }
}

private struct DownloadRow: View {
    let download: DownloadManager.Download

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(download.name)
                .lineLimit(1)
            switch download.state {
            case .running:
                ProgressView(value: download.progress)
                    .tint(.appPurple)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .finished:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.appPurple)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusText: String {
        let received = ByteCountFormatter.string(fromByteCount: download.received, countStyle: .file)
        guard download.expected > 0 else { return received }
        let expected = ByteCountFormatter.string(fromByteCount: download.expected, countStyle: .file)
        return "\(received) of \(expected)"
    }
}
