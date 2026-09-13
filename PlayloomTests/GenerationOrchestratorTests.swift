import Foundation
import XCTest
@testable import Playloom

@MainActor
final class GenerationOrchestratorTests: XCTestCase {
    func testStopCancelsProviderAndPersistsHonestReport() async throws {
        let projectID = ProjectID()
        let journalURL = FileManager.default.temporaryDirectory.appending(path: "playloom-cancel-journal-\(UUID().uuidString).json")
        let workspaceURL = FileManager.default.temporaryDirectory.appending(path: "playloom-cancel-workspace-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: workspaceURL)
        }

        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let provider = CancellationProvider()
        let orchestrator = GenerationOrchestrator(
            projectID: projectID,
            provider: provider,
            journal: journal,
            workspace: try ProjectWorkspace(root: workspaceURL),
            runtimeCheck: { _ in RuntimeReport(passed: [], failures: ["unexpected runtime call"], console: []) },
            setIdleTimerDisabled: { _ in }
        )

        let task = await orchestrator.startGenerate(prompt: "Make a game")
        var started = false
        for _ in 0..<100 {
            started = await provider.hasStarted()
            if started { break }
            await Task.yield()
        }
        XCTAssertTrue(started)

        orchestrator.cancel()
        let result = await task.value
        let snapshot = await journal.snapshot()
        let run = try XCTUnwrap(snapshot.runs.last)

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertNil(result.project)
        XCTAssertEqual(run.lifecycle, .cancelled)
        XCTAssertEqual(run.outcome?.status, .cancelled)
        XCTAssertNil(snapshot.passingProject)
        XCTAssertTrue(run.events.contains { $0.kind == .cancellationRequested })
        XCTAssertTrue(run.events.contains { $0.kind == .cancelled })
        XCTAssertFalse(orchestrator.isWorking)
        XCTAssertNil(orchestrator.project)

        var replayIterator = orchestrator.eventStream().makeAsyncIterator()
        let replayed = await replayIterator.next()
        XCTAssertEqual(replayed?.runID, result.runID)
        XCTAssertTrue(orchestrator.events.filter { $0.runID == result.runID }.allSatisfy {
            $0.projectID == projectID && $0.baseRevisionID == run.baseRevisionID
        })
    }
}

private actor CancellationProvider: ModelProvider {
    nonisolated let displayName = "Cancellation Test Provider"
    private var started = false

    func hasStarted() -> Bool { started }

    func generateProject(prompt: String) async throws -> GameProject {
        started = true
        try await Task.sleep(nanoseconds: 30_000_000_000)
        throw CancellationTestError.unexpectedCompletion
    }

    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject {
        try await generateProject(prompt: instruction)
    }
}

private enum CancellationTestError: Error { case unexpectedCompletion }
