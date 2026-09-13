import Foundation

@MainActor
final class ProjectWorkspace {
    struct StagedProject: Sendable {
        let project: GameProject
        let directory: URL
    }

    private static let metadataFilename = ".playloom-candidate.json"
    private let fileManager = FileManager.default
    private let root: URL

    init(root: URL? = nil) throws {
        self.root = root ?? Self.defaultRootURL()
        try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func stage(_ project: GameProject, candidateID: CandidateID) throws -> URL {
        let project = try project.validated()
        let candidate = root.appending(path: candidateID.description, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
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
            let metadata = try JSONEncoder().encode(project)
            try metadata.write(to: candidate.appending(path: Self.metadataFilename), options: .atomic)
            try persistCIArtifactIfRequested(candidate)
            return candidate
        } catch {
            try? fileManager.removeItem(at: candidate)
            throw error
        }
    }

    func stage(_ project: GameProject) throws -> URL {
        try stage(project, candidateID: CandidateID())
    }

    func load(candidateID: CandidateID) throws -> StagedProject {
        let candidate = root.appending(path: candidateID.description, directoryHint: .isDirectory)
        let metadataURL = candidate.appending(path: Self.metadataFilename)
        let project = try JSONDecoder().decode(GameProject.self, from: Data(contentsOf: metadataURL)).validated()
        guard fileManager.fileExists(atPath: candidate.appending(path: "vendor/phaser.min.js").path) else {
            throw WorkspaceError.missingPhaser
        }
        return StagedProject(project: project, directory: candidate)
    }

    private static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Playloom/Candidates", directoryHint: .isDirectory)
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
