//
//  GitHubViewModel.swift
//  AI Runner
//

import Foundation
import SwiftUI

/// Signing in to GitHub, listing the account's repositories and cloning them.
@MainActor
final class GitHubViewModel: ObservableObject {
    /// The account's login, once the token has been checked with GitHub.
    @Published private(set) var login: String?
    @Published private(set) var hasToken = false
    @Published private(set) var repositories: [GitHubRepo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var cloningIDs: Set<Int> = []
    @Published var errorText: String?

    private let projects = ProjectsStore.shared

    var isSignedIn: Bool { login != nil }

    /// What the row in Settings says.
    var statusText: String {
        if let login { return "Signed in as @\(login)" }
        return hasToken ? "Signed out" : "Signed out"
    }

    var token: String? {
        ApiKeyManager.shared.get(key: GitHubService.tokenKey)
    }

    init() {
        hasToken = ApiKeyManager.shared.has(key: GitHubService.tokenKey)
        login = UserDefaults.standard.string(forKey: "githubLogin")
    }

    /// Checks the saved token with GitHub and loads the repositories.
    func refresh() async {
        guard let token else {
            login = nil
            hasToken = false
            repositories = []
            return
        }
        hasToken = true
        isLoading = true
        defer { isLoading = false }
        do {
            let account = try await GitHubService.account(token: token)
            login = account.login
            UserDefaults.standard.set(account.login, forKey: "githubLogin")
            errorText = nil
            repositories = try await GitHubService.repositories(token: token)
        } catch {
            login = nil
            UserDefaults.standard.removeObject(forKey: "githubLogin")
            repositories = []
            errorText = error.localizedDescription
        }
    }

    /// Saves a token and signs in with it. Returns false when GitHub rejects it.
    func signIn(with token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            let account = try await GitHubService.account(token: trimmed)
            ApiKeyManager.shared.set(key: GitHubService.tokenKey, value: trimmed)
            hasToken = true
            login = account.login
            UserDefaults.standard.set(account.login, forKey: "githubLogin")
            errorText = nil
            repositories = try await GitHubService.repositories(token: trimmed)
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func signOut() {
        ApiKeyManager.shared.remove(key: GitHubService.tokenKey)
        UserDefaults.standard.removeObject(forKey: "githubLogin")
        hasToken = false
        login = nil
        repositories = []
        errorText = nil
    }

    /// Downloads a repository into the Projects folder.
    func clone(_ repo: GitHubRepo) async {
        guard let token else {
            errorText = GitHubError.notSignedIn.localizedDescription
            return
        }
        guard !cloningIDs.contains(repo.id) else { return }
        cloningIDs.insert(repo.id)
        errorText = nil
        defer { cloningIDs.remove(repo.id) }
        do {
            _ = try await GitHubService.clone(repo, token: token, into: AppFolders.projects)
            projects.refresh()
        } catch {
            errorText = "Could not clone \(repo.name). \(error.localizedDescription)"
        }
    }

    func isCloned(_ repo: GitHubRepo) -> Bool {
        projects.exists(named: repo.name)
    }
}
