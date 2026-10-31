//
//  ContentView.swift
//  AI Runner
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var runner = LlamaRunner()
    @StateObject private var modelsViewModel = ModelsViewModel()

    var body: some View {
        TabView {
            ChatView(runner: runner, settings: settings)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            ModelsView(runner: runner, modelsViewModel: modelsViewModel, settings: settings)
                .tabItem {
                    Label("Models", systemImage: "cube.transparent")
                }

            ImageGenerationView(settings: settings)
                .tabItem {
                    Label("Image", systemImage: "photo.on.rectangle.angled")
                }

            SettingsView(settings: settings, runner: runner)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.appAmber)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}