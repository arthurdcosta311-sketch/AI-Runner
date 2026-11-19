//
//  HuggingFaceAPI.swift
//  AI Runner
//

import Foundation

/// A model repository found by searching Hugging Face.
struct HFModel: Identifiable, Hashable {
    let id: String
    let downloads: Int
}

/// A GGUF file inside a Hugging Face repository.
struct HFFile: Identifiable, Hashable {
    let name: String
    let size: Int64

    var id: String { name }

    func downloadURL(repo: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(name)?download=true")
    }
}

/// Searches Hugging Face for GGUF models and lists the files in a repository.
/// The user's token is sent when there is one, which unlocks gated repositories.
enum HuggingFaceAPI {
    static func search(_ query: String, token: String?) async throws -> [HFModel] {
        var components = URLComponents(string: "https://huggingface.co/api/models")
        components?.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "limit", value: "30")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let data = try await get(url, token: token)
        let entries = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return entries.compactMap { entry -> HFModel? in
            guard let id = entry["id"] as? String else { return nil }
            return HFModel(id: id, downloads: entry["downloads"] as? Int ?? 0)
        }
    }

    static func ggufFiles(repo: String, token: String?) async throws -> [HFFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true") else {
            throw URLError(.badURL)
        }
        let data = try await get(url, token: token)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = object["siblings"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return siblings.compactMap { file -> HFFile? in
            guard let name = file["rfilename"] as? String, name.lowercased().hasSuffix(".gguf") else { return nil }
            let size = (file["size"] as? NSNumber)?.int64Value ?? 0
            return HFFile(name: name, size: size)
        }
    }

    private static func get(_ url: URL, token: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
