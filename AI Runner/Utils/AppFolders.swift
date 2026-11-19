//
//  AppFolders.swift
//  AI Runner
//

import Foundation

/// The folders the app keeps its files in, all inside its Documents folder.
enum AppFolders {
    static let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// Downloaded and imported model files. Created on first use.
    static let models: URL = {
        let folder = AppFolders.documents.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Repositories cloned from GitHub, one folder each. Created on first use.
    static let projects: URL = {
        let folder = AppFolders.documents.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}
