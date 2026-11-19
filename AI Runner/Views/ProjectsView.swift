//
//  ProjectsView.swift
//  AI Runner
//

import SwiftUI

/// The Projects tab: repositories cloned from GitHub, browsed and edited like any folder.
struct ProjectsView: View {
    @ObservedObject private var projects = ProjectsStore.shared
    @StateObject private var github = GitHubViewModel()
    @State private var showingGitHub = false

    var body: some View {
        NavigationStack {
            Group {
                if projects.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No projects yet", systemImage: "chevron.left.forwardslash.chevron.right")
                    } description: {
                        Text(github.isSignedIn
                             ? "Pick a repository on GitHub and tap Clone. It appears here with all its files."
                             : "Sign in to GitHub, then clone one of your repositories here.")
                    } actions: {
                        Button {
                            showingGitHub = true
                        } label: {
                            Label("Open GitHub", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.appPurple)
                    }
                } else {
                    List {
                        ForEach(projects.projects) { project in
                            NavigationLink {
                                FolderView(folder: project.url, title: project.name)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        .font(.title3)
                                        .foregroundStyle(.appPurple)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(.headline)
                                        Text("\(project.itemCount) items")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGitHub = true
                    } label: {
                        Image(systemName: github.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    }
                    .accessibilityLabel("GitHub")
                }
            }
            .sheet(isPresented: $showingGitHub) {
                NavigationStack {
                    GitHubView(model: github, showsDoneButton: true)
                }
                .tint(.appPurple)
            }
            .onAppear {
                projects.refresh()
                Task { await github.refresh() }
            }
            .refreshable {
                projects.refresh()
                await github.refresh()
            }
            .animation(.smooth, value: projects.projects.count)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            projects.delete(projects.projects[index])
        }
    }
}
