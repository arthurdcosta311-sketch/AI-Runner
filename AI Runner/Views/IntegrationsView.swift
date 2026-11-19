//
//  IntegrationsView.swift
//  AI Runner
//

import SwiftUI

/// Connects the models to MCP servers. GitHub sign in lives in Settings.
struct IntegrationsView: View {
    @ObservedObject var settings: AppSettings

    @State private var showingAddServer = false
    @State private var serverName = ""
    @State private var serverURL = ""
    @State private var serverToken = ""
    @State private var serverError: String?

    var body: some View {
        Form {
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
