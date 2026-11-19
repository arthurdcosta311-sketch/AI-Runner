//
//  GitHubService.swift
//  AI Runner
//

import Foundation

/// The GitHub account a token belongs to.
struct GitHubAccount: Decodable {
    let login: String
    let name: String?
}

/// A repository on GitHub.
struct GitHubRepo: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let summary: String?
    let isPrivate: Bool
    let defaultBranch: String
    let language: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, language
        case fullName = "full_name"
        case summary = "description"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case updatedAt = "updated_at"
    }
}

enum GitHubError: LocalizedError {
    case unauthorized
    case notSignedIn
    case rateLimited
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "GitHub didn't accept that token. Check it has not expired, then sign in again."
        case .notSignedIn:
            return "Sign in to GitHub first."
        case .rateLimited:
            return "GitHub is rate limiting this token. Wait a minute and try again."
        case .http(let status, let message):
            return "GitHub returned status \(status). \(message)"
        case .badResponse:
            return "GitHub sent a reply that could not be read."
        }
    }
}

/// Talks to the GitHub REST API, and unpacks a repository into the app's Projects folder.
///
/// A repository is "cloned" by downloading GitHub's archive of the branch and unpacking
/// it, so the project's files appear on the phone. It is the source, not a git checkout:
/// there is no history and no way to push from the app.
enum GitHubService {
    static let tokenKey = "GITHUB_TOKEN"

    static func account(token: String) async throws -> GitHubAccount {
        try await get("user", token: token)
    }

    static func repositories(token: String) async throws -> [GitHubRepo] {
        try await get("user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member",
                      token: token)
    }

    /// Downloads the repository's branch and unpacks it into `folder`. Returns the new folder.
    static func clone(_ repo: GitHubRepo, token: String, into folder: URL) async throws -> URL {
        guard let url = URL(string: "https://api.github.com/repos/\(repo.fullName)/zipball/\(repo.defaultBranch)") else {
            throw GitHubError.badResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.badResponse }
        if http.statusCode == 401 { throw GitHubError.unauthorized }
        if http.statusCode == 403 || http.statusCode == 429 { throw GitHubError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.http(http.statusCode, "The repository could not be downloaded.")
        }

        let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
        let archive = try ZipArchive(data: data)

        let destination = DownloadManager.uniqueURL(for: repo.name, in: folder)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try archive.extractAll(into: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        try? FileManager.default.removeItem(at: temporary)
        return destination
    }

    // MARK: - Requests

    private static func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: "https://api.github.com/" + path) else { throw GitHubError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.badResponse }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            throw GitHubError.rateLimited
        default:
            throw GitHubError.http(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError.badResponse
        }
    }
}
