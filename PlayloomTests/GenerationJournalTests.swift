import Foundation
import XCTest
@testable import Playloom

final class GenerationJournalTests: XCTestCase {
    private let projectID = ProjectID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
    private let baseRevisionID = BaseRevisionID(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)

    func testSchemaJSONRoundTripPreservesTypedRecordsAndStableIDs() throws {
        let operation = GenerationOperation(id: OperationID(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!), kind: .generate, stage: .generating, candidateID: CandidateID(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!), baseRevisionID: baseRevisionID, retryRound: 1)
        let plan = GenerationPlan(coreLoop: "Dodge stars", actions: ["move"], controls: ["touch"], entities: ["player", "star"], winConditions: ["survive"], loseConditions: ["hit"], doneWhenChecks: ["player responds"])
        let run = GenerationRun(projectID: projectID, id: RunID(UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!), createdAt: Date(timeIntervalSince1970: 10), lifecycle: .foreground, baseRevisionID: baseRevisionID, plan: plan, operations: [operation], events: [], outcome: nil)
        let data = try JSONEncoder().encode(run)
        XCTAssertEqual(try JSONDecoder().decode(GenerationRun.self, from: data), run)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"))
    }

    func testJournalPersistsAndReloadsStableIDsAndEventOrder() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let runID = RunID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let journal = try RunJournal(fileURL: url, projectID: projectID, now: { Date(timeIntervalSince1970: 20) })
        try await journal.createRun(baseRevisionID: baseRevisionID, runID: runID)
        try await journal.append(event(summary: "Planning", runID: runID, kind: .stageStarted, stage: .planning))
        try await journal.append(event(summary: "Generated", runID: runID, kind: .stageFinished, stage: .generating))

        let reloaded = try RunJournal(fileURL: url, projectID: projectID)
        let snapshot = await reloaded.snapshot()
        XCTAssertEqual(snapshot.activeRunID, runID)
        XCTAssertEqual(snapshot.runs.first?.events.map(\.summary), ["Run created", "Planning", "Generated"])
        XCTAssertEqual(snapshot.runs.first?.id, runID)
    }

    func testSimulatedRelaunchMarksInFlightRunInterrupted() async throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let journal = try RunJournal(fileURL: url, projectID: projectID)
        let runID = try await journal.createRun(baseRevisionID: baseRevisionID)
        let recoveredID = try await journal.recoverInFlightRun(as: .osRelaunchInterrupted)
        let lifecycle = (await journal.snapshot()).runs.first?.lifecycle
        XCTAssertEqual(recoveredID, runID)
        XCTAssertEqual(lifecycle, .relaunchedInterrupted)
    }

    func testForceQuitIsClassifiedSeparately() async throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url) }
        let journal = try RunJournal(fileURL: url, projectID: projectID)
        _ = try await journal.createRun(baseRevisionID: baseRevisionID)
        _ = try await journal.recoverInFlightRun(as: .forceQuitUnknown)
        let lifecycle = (await journal.snapshot()).runs.first?.lifecycle
        XCTAssertEqual(lifecycle, .forceQuitUnknown)
    }

    func testEncodedEventContainsNoRawProviderFields() throws {
        let event = event(summary: "Provider output received", runID: RunID(), kind: .stageFinished, stage: .generating)
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        for forbidden in ["prompt", "response", "reasoning", "credential", "percentage", "source"] {
            XCTAssertFalse(json.lowercased().contains(forbidden), "found forbidden field \(forbidden)")
        }
    }

    func testFinalizationPersistsOutcomeAndTerminalEventTogether() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let runID = RunID()
        let journal = try RunJournal(fileURL: url, projectID: projectID)
        try await journal.createRun(baseRevisionID: baseRevisionID, runID: runID)
        let outcome = GenerationOutcome(status: .completed, timestamp: Date(timeIntervalSince1970: 40), summary: "Playable", detail: "Basic runtime passed.", candidateID: nil, durationMilliseconds: 12, usage: nil)
        let terminalEvent = event(summary: "Playable", runID: runID, kind: .completed, stage: .checking).with(lifecycle: .completed, durationMilliseconds: 12)
        let passingProject = PassingProjectMetadata(baseRevisionID: baseRevisionID, title: "Passing game", filePaths: ["index.html"], updatedAt: Date(timeIntervalSince1970: 41))

        try await journal.finalize(outcome, with: terminalEvent, runID: runID, passingProject: passingProject)

        let reloaded = try RunJournal(fileURL: url, projectID: projectID)
        let snapshot = await reloaded.snapshot()
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertEqual(snapshot.runs.first?.outcome, outcome)
        XCTAssertEqual(snapshot.runs.first?.events.last, terminalEvent)
        XCTAssertEqual(snapshot.runs.first?.lifecycle, .completed)
        XCTAssertEqual(snapshot.passingProject, passingProject)
    }

    func testJournalRejectsBackgroundTransferWithoutFullRunIdentity() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let runID = try await RunJournal(fileURL: url, projectID: projectID).createRun(baseRevisionID: baseRevisionID)
        let missingCandidate = BackgroundTransferMetadata(
            taskIdentifier: 61,
            projectID: projectID,
            runID: runID,
            operationID: OperationID(),
            candidateID: nil,
            baseRevisionID: baseRevisionID,
            state: .completed
        )
        let journal = try RunJournal(fileURL: url, projectID: projectID)

        do {
            try await journal.recordBackgroundTransfer(missingCandidate, runID: runID)
            XCTFail("Expected incomplete transfer identity to be rejected")
        } catch RunJournalError.invalidEvent {
            // Expected: transport records are never journaled without operation,
            // candidate, and base identities.
        }

        let transfers = await journal.backgroundTransfers(for: runID)
        let activeRunID = (await journal.snapshot()).activeRunID
        XCTAssertTrue(transfers.isEmpty)
        XCTAssertEqual(activeRunID, runID)
    }

    private func event(summary: String, runID: RunID, kind: GenerationEventKind, stage: GenerationStage) -> GenerationEvent {
        GenerationEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 30), projectID: projectID, runID: runID, candidateID: nil, operationID: nil, baseRevisionID: baseRevisionID, kind: kind, lifecycle: nil, stage: stage, summary: summary, detail: nil, check: nil, fileDiff: nil, retryRound: nil, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil)
    }

    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appending(path: "playloom-journal-\(UUID().uuidString).json") }
}

private extension GenerationEvent {
    func with(lifecycle: RunLifecycle, durationMilliseconds: Int?) -> GenerationEvent {
        GenerationEvent(id: id, timestamp: timestamp, projectID: projectID, runID: runID, candidateID: candidateID, operationID: operationID, baseRevisionID: baseRevisionID, kind: kind, lifecycle: lifecycle, stage: stage, summary: summary, detail: detail, check: check, fileDiff: fileDiff, retryRound: retryRound, durationMilliseconds: durationMilliseconds, usage: usage, backgroundTransfer: backgroundTransfer)
    }
}
