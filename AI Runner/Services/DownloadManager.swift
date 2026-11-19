//
//  DownloadManager.swift
//  AI Runner
//

import Foundation

/// Downloads files from the internet into the app's folders. There is no size cap:
/// each file streams to disk as it arrives, so a large model never sits in memory.
/// All delegate callbacks run on the main queue, so the published state needs no locks.
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    struct Download: Identifiable, Equatable {
        enum State: Equatable {
            case running
            case finished
            case failed(String)
        }

        let id: UUID
        let name: String
        var state: State = .running
        var received: Int64 = 0
        var expected: Int64 = 0

        var progress: Double {
            expected > 0 ? min(1, Double(received) / Double(expected)) : 0
        }
    }

    private struct Job {
        let downloadID: UUID
        let destination: URL
    }

    @Published private(set) var downloads: [Download] = []
    private var jobs: [Int: Job] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    /// How many downloads have finished, so screens can refresh their file lists.
    var finishedCount: Int {
        downloads.filter { $0.state == .finished }.count
    }

    /// Starts a download into `folder` and returns at once. A name already taken gets a number.
    func start(_ url: URL, into folder: URL, token: String? = nil) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let name = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let destination = Self.uniqueURL(for: name, in: folder)
        let download = Download(id: UUID(), name: destination.lastPathComponent)
        downloads.insert(download, at: 0)

        let task = session.downloadTask(with: request)
        jobs[task.taskIdentifier] = Job(downloadID: download.id, destination: destination)
        task.resume()
    }

    /// Removes the rows for downloads that have finished or failed.
    func clearFinished() {
        downloads.removeAll { $0.state != .running }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let job = jobs[downloadTask.taskIdentifier], let index = index(of: job.downloadID) else { return }
        downloads[index].received = totalBytesWritten
        downloads[index].expected = totalBytesExpectedToWrite
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let job = jobs[downloadTask.taskIdentifier], let index = index(of: job.downloadID) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            downloads[index].state = .failed(Self.describe(status: http.statusCode))
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: job.destination)
            downloads[index].state = .finished
        } catch {
            downloads[index].state = .failed(error.localizedDescription)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let job = jobs.removeValue(forKey: task.taskIdentifier) else { return }
        if let error, let index = index(of: job.downloadID) {
            downloads[index].state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func index(of id: UUID) -> Int? {
        downloads.firstIndex { $0.id == id }
    }

    /// A file name in `folder` that is not taken yet: "model.gguf", then "model 2.gguf", and so on.
    static func uniqueURL(for name: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    private static func describe(status: Int) -> String {
        switch status {
        case 401, 403:
            return "Access denied (\(status)). Gated models need a Hugging Face token: add one in Models."
        case 404:
            return "Not found (404). Check the address."
        default:
            return "The server returned status \(status)."
        }
    }
}
