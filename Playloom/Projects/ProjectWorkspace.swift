import Foundation

@MainActor
final class ProjectWorkspace {
    private let fileManager = FileManager.default
    private let root: URL

    init(root: URL? = nil) throws {
        self.root = root ?? fileManager.temporaryDirectory.appending(path: "PlayloomWorkspace", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func stage(_ project: GameProject) throws -> URL {
        let project = try project.validated()
        let candidate = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        do {
            for (path, content) in project.files {
                let destination = candidate.appending(path: path)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: destination, atomically: true, encoding: .utf8)
            }
            guard let phaser = Bundle.main.url(forResource: "phaser.min", withExtension: "js", subdirectory: "Phaser")
                    ?? Bundle.main.url(forResource: "phaser.min", withExtension: "js") else { throw WorkspaceError.missingPhaser }
            let vendor = candidate.appending(path: "vendor", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: vendor, withIntermediateDirectories: true)
            try fileManager.copyItem(at: phaser, to: vendor.appending(path: "phaser.min.js"))
            try persistCIArtifactIfRequested(candidate)
            return candidate
        } catch {
            try? fileManager.removeItem(at: candidate)
            throw error
        }
    }

    private func persistCIArtifactIfRequested(_ candidate: URL) throws {
        guard let artifactRoot = ProcessInfo.processInfo.environment["PLAYLOOM_ARTIFACT_DIR"], !artifactRoot.isEmpty else { return }
        let root = URL(fileURLWithPath: artifactRoot, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appending(path: candidate.lastPathComponent, directoryHint: .isDirectory)
        try fileManager.copyItem(at: candidate, to: destination)
    }
}

nonisolated enum WorkspaceError: Error { case missingPhaser }
