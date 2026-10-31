//
//  SettingsView.swift
//  AI Runner
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var runner: LlamaRunner
    @State private var diagnostics: String = ""

    var body: some View {
        NavigationStack {
            Form {
                inferenceSection
                webSection
                huggingFaceSection
                imageSection
                debugSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Sections

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
                    .tint(.appAmber)
            }
            Stepper(value: $settings.maxTokens, in: 64...4096, step: 64) {
                LabeledContent("Max response tokens", value: "\(settings.maxTokens)")
            }
        }
    }

    private var webSection: some View {
        Section {
            Toggle(isOn: $settings.webAccessEnabled) {
                Label("Web access", systemImage: "globe")
            }
        } footer: {
            Text("When on, the model can ask the app to fetch a web page with a `FETCH <url>` command and use it in its answer.")
        }
    }

    private var huggingFaceSection: some View {
        Section {
            LabeledContent("Token", value: settings.hasHuggingFaceToken ? "Saved ✓" : "Not set")
        } header: {
            Text("Hugging Face")
        } footer: {
            Text(settings.hasHuggingFaceToken
                 ? "Your token is stored securely in the keychain and used for model downloads and image generation. Enter it once by tapping Run and following the prompt."
                 : "To add your token, tap Run and enter it when the app asks. It is stored in the keychain, never in the code. Create one at huggingface.co/settings/tokens.")
        }
    }

    private var imageSection: some View {
        Section {
            TextField("Model id", text: $settings.imageModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Image generation")
        } footer: {
            Text("Hugging Face model used for text-to-image. Works only with the token above.")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle(isOn: $settings.jitDebugEnabled) {
                Label("JIT — extended memory debugging", systemImage: "antenna.radiowaves.left.and.right")
            }
            .onChange(of: settings.jitDebugEnabled) { enabled in
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