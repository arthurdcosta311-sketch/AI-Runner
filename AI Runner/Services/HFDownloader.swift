//
//  HFDownloader.swift
//  AI Runner
//

import Foundation

/// A GGUF download in progress or finished.
struct DownloadItem: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case downloading
        case finished
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let fileName: String
    var state: State = .waiting
    var progress: Double = 0
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
}

/// Downloads GGUF files (from Hugging Face or anywhere) into the app's
/// Models folder, using the Hugging Face token when one is set.
final class HFDownloader: ObservableObject {
    static let modelsDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let models = documents.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        return models
    }()

    @Published private(set) var items: [DownloadItem] = []

    /// Starts a download. The returned task can be cancelled.
    @discardableResult
    func startDownload(from url: URL, token: String?, completion: @escaping (Result<URL, Error>) -> Void) -> URLSessionDataTask? {
        let fileName = url.lastPathComponent.isEmpty ? "model.gguf" : url.lastPathComponent
        let destination = Self.modelsDirectory.appendingPathComponent(fileName)

        var item = DownloadItem(url: url, fileName: fileName)
        item.state = .downloading
        DispatchQueue.main.async { self.items.append(item) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    self.fail(item, message: error.localizedDescription)
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse, let data else {
                    self.fail(item, message: "Download failed")
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let message = http.statusCode == 401 || http.statusCode == 403
                        ? "Access denied (\(http.statusCode)). This model may need a Hugging Face token — add one in Settings."
                        : "Server returned status \(http.statusCode)"
                    self.fail(item, message: message)
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    try data.write(to: destination, options: .atomic)
                    self.finish(item)
                    completion(.success(destination))
                } catch {
                    self.fail(item, message: error.localizedDescription)
                    completion(.failure(error))
                }
            }
        }
        // Track progress by observing response bytes as they arrive.
        progressObserver(for: item, task: task)
        task.resume()
        return task
    }

    private func progressObserver(for item: DownloadItem, task: URLSessionDataTask) {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            guard task.state == .running else {
                timer.invalidate()
                return
            }
            DispatchQueue.main.async {
                guard let index = self.items.firstIndex(where: { $0.id == item.id }) else {
                    timer.invalidate()
                    return
                }
                self.items[index].receivedBytes = Int64(task.countOfBytesReceived)
                self.items[index].totalBytes = task.countOfBytesExpectedToReceive
                if task.countOfBytesExpectedToReceive > 0 {
                    self.items[index].progress = Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive)
                }
            }
        }
    }

    private func finish(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].state = .finished
        items[index].progress = 1
    }

    private func fail(_ item: DownloadItem, message: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].state = .failed(message)
    }
}