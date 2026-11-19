//
//  SettingsView.swift
//  AI Runner
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var runner: LlamaRunner
    @Environment(\.dismiss) private var dismiss
    @StateObject private var github = GitHubViewModel()
    @State private var diagnostics: String = ""

    var body: some View {
        NavigationStack {
            Form {
                githubSection
                inferenceSection
                toolsSection
                integrationsSection
                debugSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await github.refresh() }
        }
    }

    // MARK: - Sections

    private var githubSection: some View {
        Section {
            NavigationLink {
                GitHubView(model: github)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: github.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(github.isSignedIn ? Color.appPurple : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub")
                        Text(github.isSignedIn ? "Signed in as @\(github.login ?? "")" : "Signed out")
                            .font(.caption)
                            .foregroundStyle(github.isSignedIn ? Color.appPurple : Color.secondary)
                    }
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in to GitHub to list your projects and clone them into the Projects tab.")
        }
    }

    private var inferenceSection: some View {
        Section("Inference") {
            TextField("System prompt", text: $settings.systemPrompt, axis: .vertical)
                .lineLimit(3...6)
            Picker("Prompt template", selection: $settings.template) {
                ForEach(PromptTemplate.allCases) { template in
                    Text(template.rawValue).tag(template)
                }
            }
            Picker("Context size", selection: $settings.contextSize) {
                ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { size in
                    Text("\(size) tokens").tag(size)
                }
            }
            VStack(alignment: .leading) {
                LabeledContent("Temperature", value: settings.temperature.formatted(.number.precision(.fractionLength(2))))
                Slider(value: $settings.temperature, in: 0...1.5, step: 0.05)
                    .tint(.appPurple)
            }
            Stepper(value: $settings.maxTokens, in: 64...4096, step: 64) {
                LabeledContent("Max response tokens", value: "\(settings.maxTokens)")
            }
        }
    }

    private var toolsSection: some View {
        Section {
            Toggle(isOn: $settings.webAccessEnabled) {
                Label("Let the model use tools", systemImage: "wrench.and.screwdriver")
            }
            .tint(.appPurple)
        } header: {
            Text("Tools")
        } footer: {
            Text("The model can FETCH a page, SEARCH the web with the Focus engine, CURL a URL, RUN JS or RUN LUA on the phone, call GITHUB and call MCP servers. It uses them only when it needs them.")
        }
    }

    private var integrationsSection: some View {
        Section {
            NavigationLink {
                IntegrationsView(settings: settings)
            } label: {
                Label("Integrations", systemImage: "puzzlepiece.extension")
            }
        } footer: {
            Text("Add MCP servers the model can call.")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle(isOn: $settings.jitDebugEnabled) {
                Label("JIT — extended memory debugging", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tint(.appPurple)
            .onChange(of: settings.jitDebugEnabled) { _, enabled in
                if enabled {
                    diagnostics = LlamaRunner.diagnostics()
                }
            }
            if settings.jitDebugEnabled {
                Text(diagnostics.isEmpty ? LlamaRunner.diagnostics() : diagnostics)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Optional. Turns on extended memory debugging: memory-footprint tracking, memory-map diagnostics and a JIT availability check. Off by default.")
        }
    }
}
