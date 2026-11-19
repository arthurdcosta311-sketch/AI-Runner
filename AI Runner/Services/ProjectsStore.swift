//
//  ProjectsStore.swift
//  AI Runner
//

import Foundation

/// A repository cloned into the app's Projects folder.
struct ProjectFolder: Identifiable, Hashable {
    let url: URL
    let itemCount: Int

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// The list of cloned projects, shared by the Projects tab and the GitHub screen.
final class ProjectsStore: ObservableObject {
    static let shared = ProjectsStore()

    @Published private(set) var projects: [ProjectFolder] = []

    private init() {
        refresh()
    }

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: AppFolders.projects,
                                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
        projects = urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
            .map { url -> ProjectFolder in
                let items = (try? FileManager.default.contentsOfDirectory(at: url,
                                                                          includingPropertiesForKeys: nil,
                                                                          options: [.skipsHiddenFiles])) ?? []
                return ProjectFolder(url: url, itemCount: items.count)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func delete(_ project: ProjectFolder) {
        try? FileManager.default.removeItem(at: project.url)
        refresh()
    }

    func exists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: AppFolders.projects.appendingPathComponent(name).path)
    }
}
