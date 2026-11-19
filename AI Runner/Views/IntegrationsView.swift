//
//  IntegrationsView.swift
//  AI Runner
//

import SwiftUI

/// Connects the models to outside services: GitHub with a personal token, and MCP servers.
struct IntegrationsView: View {
    @ObservedObject var settings: AppSettings

    @State private var hasGitHub = false
    @State private var githubDraft = ""
    @State private var showingAddServer = false
    @State private var serverName = ""
    @State private var serverURL = ""
    @State private var serverToken = ""
    @State private var serverError: String?

    var body: some View {
        Form {
            Section {
                if hasGitHub {
                    Label("Token saved in the keychain", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.appPurple)
                    Button("Remove token", role: .destructive) {
                        ApiKeyManager.shared.remove(key: "GITHUB_TOKEN")
                        hasGitHub = false
                    }
                } else {
                    SecureField("GitHub personal access token", text: $githubDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save token") {
                        let token = githubDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !token.isEmpty else { return }
                        ApiKeyManager.shared.set(key: "GITHUB_TOKEN", value: token)
                        githubDraft = ""
                        hasGitHub = true
                    }
                    .disabled(githubDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("GitHub")
            } footer: {
                Text("Lets the model read GitHub with GITHUB followed by an API path, such as repos/apple/swift/issues. Create a token at github.com/settings/tokens.")
            }

            Section {
                ForEach(settings.mcpServers) { server in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                        Text(server.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete(perform: deleteServers)

                Button {
                    showingAddServer = true
                } label: {
                    Label("Add MCP server", systemImage: "plus.circle")
                }
            } header: {
                Text("MCP servers")
            } footer: {
                Text("Remote MCP servers over https. The model calls them with MCP, the server name, the tool and its JSON arguments. Tokens are kept in the keychain.")
            }
        }
        .navigationTitle("Integrations")
        .onAppear {
            hasGitHub = settings.hasGitHubToken
        }
        .sheet(isPresented: $showingAddServer) {
            addServerSheet
        }
        .animation(.smooth, value: settings.mcpServers.count)
    }

    private var addServerSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, no spaces, e.g. docs", text: $serverName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("https://example.com/mcp", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token (optional)", text: $serverToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let serverError {
                    Section {
                        Text(serverError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add MCP server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddServer = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addServer() }
                        .disabled(serverName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addServer() {
        let name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(" ") else {
            serverError = "Give the server a name without spaces."
            return
        }
        guard let parsed = URL(string: address), parsed.scheme?.lowercased() == "https" else {
            serverError = "The address must start with https://."
            return
        }
        guard !settings.mcpServers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            serverError = "A server named \(name) is already added."
            return
        }

        let server = MCPServer(name: name, url: address)
        if !serverToken.isEmpty {
            ApiKeyManager.shared.set(key: server.tokenKey, value: serverToken)
        }
        settings.mcpServers.append(server)
        serverName = ""
        serverURL = ""
        serverToken = ""
        serverError = nil
        showingAddServer = false
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            ApiKeyManager.shared.remove(key: settings.mcpServers[index].tokenKey)
        }
        settings.mcpServers.remove(atOffsets: offsets)
    }
}
