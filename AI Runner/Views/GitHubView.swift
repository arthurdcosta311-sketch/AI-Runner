//
//  GitHubView.swift
//  AI Runner
//

import SwiftUI

/// GitHub sign in, and the account's repositories with a Clone button on each.
struct GitHubView: View {
    @ObservedObject var model: GitHubViewModel
    @ObservedObject private var projects = ProjectsStore.shared
    @Environment(\.dismiss) private var dismiss

    var showsDoneButton = false

    @State private var tokenDraft = ""
    @State private var isSigningIn = false

    var body: some View {
        Form {
            accountSection

            if model.isSignedIn {
                repositoriesSection
            }

            if let errorText = model.errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("GitHub")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .animation(.smooth, value: model.isSignedIn)
        .animation(.smooth, value: model.repositories.count)
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        Section {
            Label(model.isSignedIn ? "Signed in as @\(model.login ?? "")" : "Signed out",
                  systemImage: model.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                .foregroundStyle(model.isSignedIn ? Color.appPurple : Color.secondary)

            if model.isSignedIn {
                Button("Sign out", role: .destructive) {
                    model.signOut()
                    tokenDraft = ""
                }
            } else {
                SecureField("Personal access token", text: $tokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task {
                        isSigningIn = true
                        defer { isSigningIn = false }
                        if await model.signIn(with: tokenDraft) {
                            tokenDraft = ""
                        }
                    }
                } label: {
                    HStack {
                        if isSigningIn { ProgressView().padding(.trailing, 4) }
                        Text(isSigningIn ? "Signing in…" : "Sign in with GitHub")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSigningIn || tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Account")
        } footer: {
            Text(model.isSignedIn
                 ? "Your token is kept in the keychain and used for listing and cloning your repositories, and for the model's GITHUB tool."
                 : "Sign in with a personal access token: GitHub sign in here needs no password or browser. Create one at github.com/settings/tokens with the repo scope.")
        }
    }

    @ViewBuilder
    private var repositoriesSection: some View {
        Section {
            if model.repositories.isEmpty && model.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if model.repositories.isEmpty {
                Text("No repositories on this account.")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.repositories) { repo in
                RepositoryRow(repo: repo,
                              isCloning: model.cloningIDs.contains(repo.id),
                              isCloned: projects.exists(named: repo.name)) {
                    Task { await model.clone(repo) }
                }
            }
        } header: {
            Text("Your projects")
        } footer: {
            Text("Clone downloads the repository into the Projects tab, where you can browse and edit its files.")
        }
    }
}

private struct RepositoryRow: View {
    let repo: GitHubRepo
    let isCloning: Bool
    let isCloned: Bool
    let clone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.headline)
                        .lineLimit(1)
                    if repo.isPrivate {
                        Text("private")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                    }
                }
                if let summary = repo.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let language = repo.language {
                        Text(language)
                    }
                    if let updated = repo.updatedAt {
                        Text(updated.formatted(.relative(presentation: .named)))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if isCloning {
                ProgressView()
                    .tint(.appPurple)
            } else if isCloned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.appPurple)
                    .accessibilityLabel("Cloned")
            } else {
                Button("Clone", action: clone)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.appPurple)
            }
        }
    }
}
