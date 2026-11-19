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

            ProjectsView()
                .tabItem {
                    Label("Projects", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            FilesView()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            ModelsView(runner: runner, modelsViewModel: modelsViewModel, settings: settings)
                .tabItem {
                    Label("Models", systemImage: "cube.transparent")
                }

            CreateView(settings: settings)
                .tabItem {
                    Label("Create", systemImage: "sparkles")
                }
        }
        .tint(.appPurple)
    }
}

#Preview {
    ContentView()
}
