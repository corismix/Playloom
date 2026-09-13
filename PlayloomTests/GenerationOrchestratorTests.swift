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

    func testNormalCompletionAcknowledgesOnlyAfterDurableCandidateCheckpoint() async throws {
        let projectID = ProjectID()
        let journalURL = temporaryURL("ack-order-journal")
        let workspaceURL = temporaryURL("ack-order-workspace")
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let workspace = try ProjectWorkspace(root: workspaceURL)
        let provider = CheckpointProvider(project: setupProject(title: "Ack order"), journal: journal, workspace: workspace)
        let orchestrator = GenerationOrchestrator(
            projectID: projectID,
            provider: provider,
            journal: journal,
            workspace: workspace,
            runtimeCheck: { _ in self.passingRuntimeReport() },
            setIdleTimerDisabled: { _ in }
        )

        let task = await orchestrator.startGenerate(prompt: "ack order")
        let result = await task.value

        XCTAssertEqual(result.status, .completed)
        XCTAssertTrue(provider.acknowledgementSawDurableCheckpoint())
        let snapshot = await journal.snapshot()
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertTrue(snapshot.runs.last?.events.contains { $0.kind == .candidateStaged } == true)
    }

    func testCompletedResponseRecoveredAcrossRecreatedOrchestratorAndTransport() async throws {
        let setup = try await makeSetup(transferState: .completed, journalizesTransfer: true)
        defer { setup.cleanup() }
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
        let first = try makeOrchestrator(setup: setup, provider: provider)

        await first.recoverOnLaunch(as: .osRelaunchInterrupted)
        let completed = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

        XCTAssertEqual(completed.outcome?.status, .completed)
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertTrue(provider.acknowledgedTaskIDs().contains(setup.taskIdentifier))
        let transferRecords = try setup.store.load()
        XCTAssertTrue(transferRecords.isEmpty)
        XCTAssertTrue(completed.events.contains { $0.kind == .candidateStaged })
        XCTAssertEqual(completed.outcome?.candidateID, setup.candidateID)
    }

    func testProductionWiringRecoversFileBackedOpenCodeEnvelopeAfterObjectRecreation() async throws {
        let projectID = ProjectID()
        let runID = RunID()
        let candidateID = CandidateID()
        let operationID = OperationID()
        let baseRevisionID = BaseRevisionID()
        let journalURL = temporaryURL("production-wiring-journal")
        let workspaceURL = temporaryURL("production-wiring-workspace")
        let transportRoot = temporaryURL("production-wiring-transport")
        let transferStoreURL = transportRoot.appending(path: "transfers.json")
        let project = setupProject(title: "Production wiring recovery")
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: workspaceURL)
            try? FileManager.default.removeItem(at: transportRoot)
        }

        let initialJournal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let operation = GenerationOperation(id: operationID, kind: .generate, stage: .generating, candidateID: candidateID, baseRevisionID: baseRevisionID, retryRound: nil)
        try await initialJournal.createRun(baseRevisionID: baseRevisionID, operation: operation, runID: runID)
        _ = try ProjectWorkspace(root: workspaceURL)

        let requestBodyURL = transportRoot.appending(path: "request.json")
        let responseURL = transportRoot.appending(path: "response.bin")
        try FileManager.default.createDirectory(at: transportRoot, withIntermediateDirectories: true)
        try Data("prompt and project source".utf8).write(to: requestBodyURL, options: .atomic)
        let content = String(data: try JSONEncoder().encode(project), encoding: .utf8)!
        let envelope = ProductionOpenCodeResponse(choices: [.init(message: .init(content: content))])
        try JSONEncoder().encode(envelope).write(to: responseURL, options: .atomic)
        let transfer = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 1201,
            requestBodyURL: requestBodyURL,
            responseURL: responseURL,
            projectID: projectID,
            runID: runID,
            operationID: operationID,
            candidateID: candidateID,
            baseRevisionID: baseRevisionID,
            state: .completed,
            responseStatus: 200,
            responseHeaders: ["Content-Type": "application/json"],
            errorDescription: nil
        )
        try ApplicationSupportTransferStore(fileURL: transferStoreURL).save([transfer])

        // Recreate every production component from its persisted paths. The
        // response is an actual OpenCode envelope, while transport state and
        // the staged candidate remain on disk between the two object graphs.
        let recreatedStore = ApplicationSupportTransferStore(fileURL: transferStoreURL)
        let recreatedTransport = BackgroundHTTPClient(
            store: recreatedStore,
            session: URLSession(configuration: .ephemeral),
            transportRoot: transportRoot
        )
        let provider = OpenCodeGoProvider(
            keyStore: ProductionWiringKeyStore(),
            session: URLSession(configuration: .ephemeral),
            conversationID: "production-wiring-test",
            backgroundClient: recreatedTransport
        )
        let recreatedJournal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let recreatedWorkspace = try ProjectWorkspace(root: workspaceURL)
        let orchestrator = GenerationOrchestrator(
            projectID: projectID,
            provider: provider,
            journal: recreatedJournal,
            workspace: recreatedWorkspace,
            runtimeCheck: { _ in self.passingRuntimeReport() },
            setIdleTimerDisabled: { _ in }
        )

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(journalURL: journalURL, projectID: projectID)
        let snapshot = await recreatedJournal.snapshot()

        XCTAssertEqual(run.outcome?.status, .completed)
        XCTAssertEqual(run.outcome?.candidateID, candidateID)
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertEqual(orchestrator.project, project)
        XCTAssertTrue(run.events.contains { $0.kind == .providerOutputReceived })
        XCTAssertTrue(run.events.contains { $0.kind == .candidateStaged })
        XCTAssertTrue(run.events.contains { $0.kind == .checkFinished })
        XCTAssertTrue(run.events.contains { $0.kind == .completed })
        XCTAssertTrue(try ApplicationSupportTransferStore(fileURL: transferStoreURL).load().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appending(path: candidateID.description, directoryHint: .isDirectory).appending(path: "vendor/phaser.min.js").path))
    }

    func testCrashImmediatelyBeforeAcknowledgementRecoversFromDurableCandidateCheckpoint() async throws {
        let setup = try await makeSetup(transferState: .completed, journalizesTransfer: true, stageCandidate: true)
        defer { setup.cleanup() }
        // This is the durable state immediately before acknowledgement: the
        // completed response is still retained while its candidate checkpoint
        // is already in the journal and workspace.
        XCTAssertEqual(try setup.store.load().count, 1)
        let hasCandidateCheckpoint = await setup.journal.hasEvent(.candidateStaged, runID: setup.runID)
        XCTAssertTrue(hasCandidateCheckpoint)
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(setup)

        XCTAssertEqual(run.outcome?.status, .completed)
        XCTAssertTrue(run.events.contains { $0.kind == .providerOutputReceived })
        XCTAssertTrue(run.events.contains { $0.kind == .candidateStaged })
        XCTAssertTrue(provider.acknowledgedTaskIDs().contains(setup.taskIdentifier))
        let transferRecords = try setup.store.load()
        XCTAssertTrue(transferRecords.isEmpty)
    }

    func testCrashImmediatelyAfterAcknowledgementReusesDurableCandidateCheckpoint() async throws {
        let setup = try await makeSetup(transferState: .completed, journalizesTransfer: true, stageCandidate: true)
        defer { setup.cleanup() }
        // The transport is gone because the acknowledgement happened after the
        // candidate checkpoint. Recovery must not need the response again.
        try setup.store.save([])
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.recoverOnLaunch(as: .forceQuitUnknown)
        let run = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

        XCTAssertEqual(run.outcome?.status, .completed)
        XCTAssertEqual(orchestrator.project?.title, setup.candidate.title)
        XCTAssertFalse(provider.didAttemptTransportRecovery())
        XCTAssertNil(snapshot.activeRunID)
    }

    func testStillRunningTransferCompletesAfterProviderAndTransportRecreation() async throws {
        let setup = try await makeSetup(transferState: .running, journalizesTransfer: false)
        defer { setup.cleanup() }
        let gate = RecoveryGate()
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate, waitsForCompletion: gate, preservesRunningTransfer: true)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        for _ in 0..<200 where !provider.isWaitingForCompletion() { await Task.yield() }
        XCTAssertTrue(provider.isWaitingForCompletion())

        let completedRecord = try setup.completedRecord()
        try setup.store.save([completedRecord])
        await gate.release()
        let run = try await waitForTerminal(setup)

        XCTAssertEqual(run.outcome?.status, .completed)
        XCTAssertTrue(provider.acknowledgedTaskIDs().contains(setup.taskIdentifier))
        let transferRecords = try setup.store.load()
        XCTAssertTrue(transferRecords.isEmpty)
    }

    func testRecoveryRestoresEditProjectAndBaseContextAcrossRelaunch() async throws {
        let current = setupProject(title: "Current")
        let edited = setupProject(title: "Edited")
        let setup = try await makeSetup(kind: .edit, candidate: edited, transferState: .completed, journalizesTransfer: true, passingProject: current)
        defer { setup.cleanup() }
        let provider = RelaunchProvider(store: setup.store, project: edited)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.loadPersistedActivity()
        XCTAssertEqual(orchestrator.project, current)
        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

        XCTAssertEqual(run.outcome?.status, .completed)
        XCTAssertEqual(orchestrator.project, edited)
        XCTAssertEqual(run.baseRevisionID, setup.baseRevisionID)
        XCTAssertEqual(snapshot.passingProject?.candidateID, setup.candidateID)
    }

    func testNoFailedCancelledOrInterruptedRecoveryBranchLeavesRunActive() async throws {
        for state in [BackgroundHTTPClient.TransferState.running, .failed, .cancelled, .interrupted] {
            let setup = try await makeSetup(transferState: state, journalizesTransfer: false)
            let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
            let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

            await orchestrator.recoverOnLaunch(as: .forceQuitUnknown)
            let run = try await waitForTerminal(setup)
            let snapshot = try await reloadSnapshot(for: setup)

            XCTAssertEqual(run.outcome?.status, .failed)
            XCTAssertNil(snapshot.activeRunID)
            XCTAssertFalse(orchestrator.isWorking)
            setup.cleanup()
        }
    }

    func testStopRequestedCancelledTransferGetsDurableCancelledOutcome() async throws {
        let setup = try await makeSetup(transferState: .cancelled, journalizesTransfer: false, cancellationRequested: true)
        defer { setup.cleanup() }
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

        XCTAssertEqual(run.outcome?.status, .cancelled)
        XCTAssertEqual(run.lifecycle, .cancelled)
        XCTAssertTrue(run.events.contains { $0.kind == .cancellationRequested })
        XCTAssertTrue(run.events.contains { $0.kind == .cancelled })
        XCTAssertNil(snapshot.activeRunID)
    }

    func testRecoveryHonorsDurableStopBeforeResumingRunningTransfer() async throws {
        let setup = try await makeSetup(transferState: .running, journalizesTransfer: false, cancellationRequested: true)
        defer { setup.cleanup() }
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(setup)

        XCTAssertEqual(run.outcome?.status, .cancelled)
        let snapshot = try await reloadSnapshot(for: setup)
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertTrue(provider.cancelledTaskIDs().contains(setup.taskIdentifier))
        XCTAssertFalse(provider.didAttemptTransportRecovery())
    }

    func testRecoveryHonorsDurableStopAfterCandidateCheckpointBeforeOrAfterAcknowledgement() async throws {
        for acknowledged in [false, true] {
            let setup = try await makeSetup(transferState: .completed, journalizesTransfer: true, stageCandidate: true, cancellationRequested: true)
            defer { setup.cleanup() }
            if acknowledged { try setup.store.save([]) }
            let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
            let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

            await orchestrator.recoverOnLaunch(as: .forceQuitUnknown)
            let run = try await waitForTerminal(setup)
            let snapshot = try await reloadSnapshot(for: setup)

            XCTAssertEqual(run.outcome?.status, .cancelled)
            XCTAssertNil(snapshot.activeRunID)
            XCTAssertNil(snapshot.passingProject)
            XCTAssertFalse(provider.acknowledgedTaskIDs().contains(setup.taskIdentifier))
            setup.cleanup()
        }
    }

    func testRecoveryWithNoTransferGetsDurableFailure() async throws {
        let setup = try await makeSetup(transferState: nil, journalizesTransfer: false)
        defer { setup.cleanup() }
        let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
        let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

        XCTAssertEqual(run.outcome?.status, .failed)
        XCTAssertEqual(run.outcome?.summary, "Recovery could not find a response")
        XCTAssertNil(snapshot.activeRunID)
    }

    func testRecoveryRejectsTransferWithWrongFullIdentity() async throws {
        for identity in [TransferIdentity.wrongProject, .wrongOperation, .wrongCandidate, .wrongBase] {
            let setup = try await makeSetup(transferState: .completed, journalizesTransfer: false, transferIdentity: identity)
            let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
            let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

            await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
            let run = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

            XCTAssertEqual(run.outcome?.status, .failed)
            XCTAssertEqual(run.outcome?.summary, "Background response rejected")
            XCTAssertNil(snapshot.activeRunID)
            setup.cleanup()
        }
    }

    func testMissingActiveRunRecordGetsDurableTerminalPlaceholder() async throws {
        let projectID = ProjectID()
        let runID = RunID()
        let baseRevisionID = BaseRevisionID()
        let journalURL = temporaryURL("missing-run")
        let workspaceURL = temporaryURL("missing-run-workspace")
        let document = RunJournalDocument(projectID: projectID, activeRunID: runID, currentBaseRevisionID: baseRevisionID, passingProject: nil, runs: [])
        try JSONEncoder().encode(document).write(to: journalURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: journalURL) }
        let workspace = try ProjectWorkspace(root: workspaceURL)
        let provider = CancellationProvider()
        let reloadedJournal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let orchestrator = GenerationOrchestrator(projectID: projectID, provider: provider, journal: reloadedJournal, workspace: workspace, runtimeCheck: { _ in self.passingRuntimeReport() }, setIdleTimerDisabled: { _ in })

        await orchestrator.recoverOnLaunch(as: .forceQuitUnknown)
        let snapshot = await reloadedJournal.snapshot()
        let run = try XCTUnwrap(snapshot.runs.first { $0.id == runID })

        XCTAssertEqual(run.outcome?.status, .failed)
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertTrue(run.events.contains { $0.kind == .failed })
        try? FileManager.default.removeItem(at: workspaceURL)
    }

    func testIncompleteTerminalRunGetsDurableFailureAndReplayEvent() async throws {
        let projectID = ProjectID()
        let runID = RunID()
        let baseRevisionID = BaseRevisionID()
        let journalURL = temporaryURL("incomplete-terminal")
        let workspaceURL = temporaryURL("incomplete-terminal-workspace")
        let run = GenerationRun(projectID: projectID, id: runID, createdAt: Date(), lifecycle: .completed, baseRevisionID: baseRevisionID, plan: nil, operations: [], events: [], outcome: nil)
        let document = RunJournalDocument(projectID: projectID, activeRunID: runID, currentBaseRevisionID: baseRevisionID, passingProject: nil, runs: [run])
        try JSONEncoder().encode(document).write(to: journalURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let orchestrator = GenerationOrchestrator(projectID: projectID, provider: CancellationProvider(), journal: journal, workspace: try ProjectWorkspace(root: workspaceURL), runtimeCheck: { _ in self.passingRuntimeReport() }, setIdleTimerDisabled: { _ in })

        await orchestrator.recoverOnLaunch(as: .forceQuitUnknown)
        let snapshot = await journal.snapshot()
        let repaired = try XCTUnwrap(snapshot.runs.first)

        XCTAssertEqual(repaired.outcome?.status, .failed)
        XCTAssertEqual(repaired.lifecycle, .failed)
        XCTAssertEqual(repaired.events.last?.kind, .failed)
        XCTAssertNil(snapshot.activeRunID)
    }

    func testTerminalOutcomeWithMismatchedEventGetsMatchingReplayRepair() async throws {
        let projectID = ProjectID()
        let runID = RunID()
        let baseRevisionID = BaseRevisionID()
        let journalURL = temporaryURL("mismatched-terminal")
        let workspaceURL = temporaryURL("mismatched-terminal-workspace")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let outcome = GenerationOutcome(status: .completed, timestamp: timestamp, summary: "Playable", detail: "Basic runtime passed.", candidateID: nil, durationMilliseconds: 10, usage: nil)
        let mismatch = GenerationEvent(id: UUID(), timestamp: timestamp, projectID: projectID, runID: runID, candidateID: nil, operationID: nil, baseRevisionID: baseRevisionID, kind: .failed, lifecycle: .failed, stage: .checking, summary: "Generation failed", detail: "Old terminal event", check: nil, fileDiff: nil, retryRound: nil, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil)
        let run = GenerationRun(projectID: projectID, id: runID, createdAt: timestamp, lifecycle: .completed, baseRevisionID: baseRevisionID, plan: nil, operations: [], events: [mismatch], outcome: outcome)
        let document = RunJournalDocument(projectID: projectID, activeRunID: runID, currentBaseRevisionID: baseRevisionID, passingProject: nil, runs: [run])
        try JSONEncoder().encode(document).write(to: journalURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let orchestrator = GenerationOrchestrator(projectID: projectID, provider: CancellationProvider(), journal: journal, workspace: try ProjectWorkspace(root: workspaceURL), runtimeCheck: { _ in self.passingRuntimeReport() }, setIdleTimerDisabled: { _ in })

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let snapshot = await journal.snapshot()
        let repaired = try XCTUnwrap(snapshot.runs.first)

        XCTAssertEqual(repaired.outcome, outcome)
        XCTAssertEqual(repaired.events.last?.kind, .completed)
        XCTAssertEqual(repaired.events.last?.lifecycle, .completed)
        XCTAssertNil(snapshot.activeRunID)
    }

    func testMissingOperationAndCandidateIdentityGetDurableFailure() async throws {
        for operation in [nil, GenerationOperation(id: OperationID(), kind: .generate, stage: .generating, candidateID: nil, baseRevisionID: BaseRevisionID(), retryRound: nil)] as [GenerationOperation?] {
            let projectID = ProjectID()
            let journalURL = temporaryURL("missing-identity-journal")
            let workspaceURL = temporaryURL("missing-identity-workspace")
            defer {
                try? FileManager.default.removeItem(at: journalURL)
                try? FileManager.default.removeItem(at: workspaceURL)
            }
            let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
            try await journal.createRun(baseRevisionID: operation?.baseRevisionID ?? BaseRevisionID(), operation: operation)
            let reloadedJournal = try RunJournal(fileURL: journalURL, projectID: projectID)
            let orchestrator = GenerationOrchestrator(
                projectID: projectID, provider: CancellationProvider(), journal: reloadedJournal,
                workspace: try ProjectWorkspace(root: workspaceURL), runtimeCheck: { _ in self.passingRuntimeReport() }, setIdleTimerDisabled: { _ in }
            )

            await orchestrator.recoverOnLaunch(as: .forceQuitUnknown)
            let run = try await waitForTerminal(journalURL: journalURL, projectID: projectID)
            let snapshot = await reloadedJournal.snapshot()

            XCTAssertEqual(run.outcome?.status, .failed)
            XCTAssertEqual(run.outcome?.summary, "Generation could not resume")
            XCTAssertNil(snapshot.activeRunID)
        }
    }

    func testStopDuringRuntimeValidationCancelsPromptlyAndKeepsLastPassingGame() async throws {
        let projectID = ProjectID()
        let journalURL = temporaryURL("runtime-cancel-journal")
        let workspaceURL = temporaryURL("runtime-cancel-workspace")
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let provider = ImmediateProvider(project: setupProject(title: "Runtime cancel"))
        let gate = RuntimeCancellationGate()
        let orchestrator = GenerationOrchestrator(
            projectID: projectID, provider: provider, journal: journal, workspace: try ProjectWorkspace(root: workspaceURL),
            runtimeCheck: { _ in try await gate.wait() }, setIdleTimerDisabled: { _ in }
        )

        let task = await orchestrator.startGenerate(prompt: "runtime cancellation")
        for _ in 0..<200 where !gate.isStarted() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(gate.isStarted())
        orchestrator.cancel()
        let result = await task.value
        let snapshot = await journal.snapshot()

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(snapshot.runs.last?.outcome?.status, .cancelled)
        XCTAssertNil(snapshot.activeRunID)
        XCTAssertNil(snapshot.passingProject)
    }

    func testUnsupportedRecoveryProviderGetsDurableFailure() async throws {
        let setup = try await makeSetup(transferState: .completed, journalizesTransfer: false)
        defer { setup.cleanup() }
        let reloadedJournal = try RunJournal(fileURL: setup.journalURL, projectID: setup.projectID)
        let orchestrator = GenerationOrchestrator(
            projectID: setup.projectID, provider: CancellationProvider(), journal: reloadedJournal, workspace: setup.workspace,
            runtimeCheck: { _ in self.passingRuntimeReport() }, setIdleTimerDisabled: { _ in }
        )

        await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
        let run = try await waitForTerminal(setup)
        let snapshot = try await reloadSnapshot(for: setup)

        XCTAssertEqual(run.outcome?.status, .failed)
        XCTAssertEqual(run.outcome?.summary, "Background response unavailable")
        XCTAssertTrue(run.outcome?.detail?.contains("cannot reattach") == true)
        XCTAssertNil(snapshot.activeRunID)
    }

    func testMissingAndCorruptResponseBytesFinalizeRecoveryFailure() async throws {
        for response in [RecoveryResponse.missing, .corrupt] {
            let setup = try await makeSetup(transferState: .completed, journalizesTransfer: false, response: response)
            let provider = RelaunchProvider(store: setup.store, project: setup.candidate)
            let orchestrator = try makeOrchestrator(setup: setup, provider: provider)

            await orchestrator.recoverOnLaunch(as: .osRelaunchInterrupted)
            let run = try await waitForTerminal(setup)
            let snapshot = try await reloadSnapshot(for: setup)

            XCTAssertEqual(run.outcome?.status, .failed)
            XCTAssertNil(snapshot.activeRunID)
            setup.cleanup()
        }
    }

    private func makeOrchestrator(setup: RecoverySetup, provider: RelaunchProvider) throws -> GenerationOrchestrator {
        let journal = try RunJournal(fileURL: setup.journalURL, projectID: setup.projectID)
        return GenerationOrchestrator(
            projectID: setup.projectID, provider: provider, journal: journal, workspace: setup.workspace,
            runtimeCheck: { _ in self.passingRuntimeReport() }, setIdleTimerDisabled: { _ in }
        )
    }

    private func passingRuntimeReport() -> RuntimeReport {
        RuntimeReport(passed: ["WebKit bridge ready", "loads", "no JavaScript crash", "canvas not blank", "heartbeat alive", "input works", "restart works"], failures: [], console: [])
    }

    private func waitForTerminal(_ setup: RecoverySetup) async throws -> GenerationRun {
        try await waitForTerminal(journalURL: setup.journalURL, projectID: setup.projectID)
    }

    private func waitForTerminal(journalURL: URL, projectID: ProjectID) async throws -> GenerationRun {
        for _ in 0..<300 {
            let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
            if let run = (await journal.snapshot()).runs.last, run.outcome != nil { return run }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Recovery did not reach a durable terminal state")
        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let snapshot = await journal.snapshot()
        guard let run = snapshot.runs.last else { throw RecoveryTestError.missingRun }
        return run
    }

    private func reloadSnapshot(for setup: RecoverySetup) async throws -> RunJournalDocument {
        let journal = try RunJournal(fileURL: setup.journalURL, projectID: setup.projectID)
        return await journal.snapshot()
    }

    private func makeSetup(
        kind: GenerationOperationKind = .generate,
        candidate: GameProject? = nil,
        transferState: BackgroundHTTPClient.TransferState?,
        journalizesTransfer: Bool,
        stageCandidate: Bool = false,
        passingProject: GameProject? = nil,
        cancellationRequested: Bool = false,
        response: RecoveryResponse = .valid,
        transferIdentity: TransferIdentity = .correct
    ) async throws -> RecoverySetup {
        let projectID = ProjectID()
        let runID = RunID()
        let candidateID = CandidateID()
        let operationID = OperationID()
        let baseRevisionID = BaseRevisionID()
        let project = candidate ?? setupProject(title: "Recovered")
        let journalURL = temporaryURL("journal")
        let workspaceURL = temporaryURL("workspace")
        let journal = try RunJournal(fileURL: journalURL, projectID: projectID)
        let workspace = try ProjectWorkspace(root: workspaceURL)
        let operation = GenerationOperation(id: operationID, kind: kind, stage: .generating, candidateID: candidateID, baseRevisionID: baseRevisionID, retryRound: nil)
        try await journal.createRun(baseRevisionID: baseRevisionID, operation: operation, runID: runID)

        if let passingProject {
            let passingCandidateID = CandidateID()
            _ = try workspace.stage(passingProject, candidateID: passingCandidateID)
            try await journal.setPassingProject(PassingProjectMetadata(baseRevisionID: baseRevisionID, candidateID: passingCandidateID, title: passingProject.title, filePaths: passingProject.files.keys.sorted(), updatedAt: Date()))
        }

        let store = DurableTransferStore()
        let record: BackgroundHTTPClient.TransferRecord?
        if let transferState {
            let identity = switch transferIdentity {
            case .correct: (projectID, runID, operationID, candidateID, baseRevisionID)
            case .wrongProject: (ProjectID(), runID, operationID, candidateID, baseRevisionID)
            case .wrongOperation: (projectID, runID, OperationID(), candidateID, baseRevisionID)
            case .wrongCandidate: (projectID, runID, operationID, CandidateID(), baseRevisionID)
            case .wrongBase: (projectID, runID, operationID, candidateID, BaseRevisionID())
            }
            let created = try makeTransferRecord(taskIdentifier: 700, projectID: identity.0, runID: identity.1, operationID: identity.2, candidateID: identity.3, baseRevisionID: identity.4, state: transferState, response: response, project: project)
            try store.save([created])
            record = created
            if journalizesTransfer {
                let metadata = metadata(for: created)
                try await journal.recordBackgroundTransfer(metadata, runID: runID)
                try await journal.append(event(runID: runID, projectID: projectID, candidateID: candidateID, operationID: operationID, baseRevisionID: baseRevisionID, kind: .providerOutputReceived, stage: .receiving, summary: "Generation response received", transfer: metadata))
            }
        } else {
            record = nil
        }

        if cancellationRequested {
            try await journal.append(event(runID: runID, projectID: projectID, candidateID: candidateID, operationID: operationID, baseRevisionID: baseRevisionID, kind: .cancellationRequested, stage: .receiving, summary: "Stopping generation", lifecycle: .foreground))
        }
        if stageCandidate {
            _ = try workspace.stage(project, candidateID: candidateID)
            try await journal.append(event(runID: runID, projectID: projectID, candidateID: candidateID, operationID: operationID, baseRevisionID: baseRevisionID, kind: .candidateStaged, stage: .staging, summary: "Candidate staged"))
        }

        return RecoverySetup(projectID: projectID, runID: runID, candidateID: candidateID, operationID: operationID, baseRevisionID: baseRevisionID, candidate: project, journalURL: journalURL, workspaceURL: workspaceURL, journal: journal, workspace: workspace, store: store, record: record)
    }

    private func makeTransferRecord(taskIdentifier: Int, projectID: ProjectID, runID: RunID, operationID: OperationID, candidateID: CandidateID?, baseRevisionID: BaseRevisionID, state: BackgroundHTTPClient.TransferState, response: RecoveryResponse, project: GameProject) throws -> BackgroundHTTPClient.TransferRecord {
        let bodyURL = temporaryURL("body")
        let responseURL = temporaryURL("response")
        try Data("prompt and project source".utf8).write(to: bodyURL, options: .atomic)
        switch response {
        case .valid:
            try JSONEncoder().encode(project).write(to: responseURL, options: .atomic)
        case .corrupt:
            try Data("not project JSON".utf8).write(to: responseURL, options: .atomic)
        case .missing:
            break
        }
        return BackgroundHTTPClient.TransferRecord(taskIdentifier: taskIdentifier, requestBodyURL: bodyURL, responseURL: responseURL, projectID: projectID, runID: runID, operationID: operationID, candidateID: candidateID, baseRevisionID: baseRevisionID, state: state, responseStatus: 200, responseHeaders: ["Content-Type": "application/json", "Authorization": "Bearer secret"], errorDescription: nil)
    }

    private func metadata(for record: BackgroundHTTPClient.TransferRecord) -> BackgroundTransferMetadata {
        BackgroundTransferMetadata(taskIdentifier: record.taskIdentifier, projectID: record.projectID, runID: record.runID, operationID: record.operationID, candidateID: record.candidateID, baseRevisionID: record.baseRevisionID, requestBodyURL: record.requestBodyURL.path, responseURL: record.responseURL.path, state: switchState(record.state), updatedAt: record.updatedAt, statusCode: record.responseStatus, responseHeaders: record.responseHeaders)
    }

    private func switchState(_ state: BackgroundHTTPClient.TransferState) -> BackgroundTransferState {
        switch state {
        case .running: .running
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        }
    }

    private func event(runID: RunID, projectID: ProjectID, candidateID: CandidateID?, operationID: OperationID?, baseRevisionID: BaseRevisionID, kind: GenerationEventKind, stage: GenerationStage?, summary: String, lifecycle: RunLifecycle? = nil, transfer: BackgroundTransferMetadata? = nil) -> GenerationEvent {
        GenerationEvent(id: UUID(), timestamp: Date(), projectID: projectID, runID: runID, candidateID: candidateID, operationID: operationID, baseRevisionID: baseRevisionID, kind: kind, lifecycle: lifecycle, stage: stage, summary: summary, detail: nil, check: nil, fileDiff: nil, retryRound: nil, durationMilliseconds: nil, usage: nil, backgroundTransfer: transfer)
    }

    private func setupProject(title: String) -> GameProject {
        GameProject(title: title, files: ["index.html": "<script src=\"vendor/phaser.min.js\"></script>", "game.js": "window.playloomProbeInput = function() {};", "style.css": "body {}"])
    }

    private func temporaryURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "playloom-m2a-\(label)-\(UUID().uuidString)")
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

private enum RecoveryResponse { case valid, corrupt, missing }
private enum TransferIdentity { case correct, wrongProject, wrongOperation, wrongCandidate, wrongBase }

private struct RecoverySetup {
    let projectID: ProjectID
    let runID: RunID
    let candidateID: CandidateID
    let operationID: OperationID
    let baseRevisionID: BaseRevisionID
    let candidate: GameProject
    let journalURL: URL
    let workspaceURL: URL
    let journal: RunJournal
    let workspace: ProjectWorkspace
    let store: DurableTransferStore
    let record: BackgroundHTTPClient.TransferRecord?

    var taskIdentifier: Int { record?.taskIdentifier ?? -1 }

    func completedRecord() throws -> BackgroundHTTPClient.TransferRecord {
        guard let record else { throw RecoveryTestError.missingTransfer }
        var completed = record
        completed.state = .completed
        completed.responseStatus = 200
        completed.updatedAt = Date()
        try JSONEncoder().encode(candidate).write(to: completed.responseURL, options: .atomic)
        return completed
    }

    func cleanup() {
        if let records = try? store.load() {
            for record in records {
                try? FileManager.default.removeItem(at: record.requestBodyURL)
                try? FileManager.default.removeItem(at: record.responseURL)
            }
        }
        try? FileManager.default.removeItem(at: journalURL)
        try? FileManager.default.removeItem(at: workspaceURL)
    }
}

private enum RecoveryTestError: Error { case missingTransfer, missingRun }

private struct ProductionOpenCodeResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct ProductionWiringKeyStore: APIKeyStoring {
    func read() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}

private actor RecoveryGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in waiters.append(continuation) }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private final class RuntimeCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    func wait() async throws -> RuntimeReport {
        lock.withLock { started = true }
        try await Task.sleep(for: .seconds(60))
        return RuntimeReport(passed: [], failures: [], console: [])
    }

    func isStarted() -> Bool { lock.withLock { started } }
}

private final class DurableTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [BackgroundHTTPClient.TransferRecord]

    init(records: [BackgroundHTTPClient.TransferRecord] = []) { self.records = records }

    func load() throws -> [BackgroundHTTPClient.TransferRecord] { lock.withLock { records } }

    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws {
        lock.withLock { self.records = records }
    }
}

private final class RelaunchProvider: BackgroundRecoveringProvider, @unchecked Sendable {
    let displayName = "Relaunch Test Provider"
    let supportsBackgroundContinuation = true
    let supportsBackgroundRecovery = true

    private let store: DurableTransferStore
    private let project: GameProject
    private let client: BackgroundHTTPClient
    private let waitsForCompletion: RecoveryGate?
    private let preservesRunningTransfer: Bool
    private let lock = NSLock()
    private var acknowledged: [Int] = []
    private var cancelled: [Int] = []
    private var waitingForCompletion = false
    private var attemptedTransportRecovery = false

    init(store: DurableTransferStore, project: GameProject, waitsForCompletion: RecoveryGate? = nil, preservesRunningTransfer: Bool = false) {
        self.store = store
        self.project = project
        self.client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        self.waitsForCompletion = waitsForCompletion
        self.preservesRunningTransfer = preservesRunningTransfer
    }

    func generateProject(prompt: String) async throws -> GameProject { project }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject { self.project }

    func recoverBackgroundTransfers(for runID: RunID) async throws -> [BackgroundHTTPClient.TransferMetadata] {
        lock.withLock { attemptedTransportRecovery = true }
        if preservesRunningTransfer {
            return client.metadata(for: runID)
        }
        return try await client.recover(for: runID)
    }

    func recoverProjectOutput(from transfer: BackgroundHTTPClient.TransferMetadata) async throws -> GenerationProviderOutput {
        lock.withLock { waitingForCompletion = true }
        if let waitsForCompletion { await waitsForCompletion.wait() }
        let recreatedClient = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let response = try await recreatedClient.waitForTransfer(taskIdentifier: transfer.taskIdentifier)
        let project = try JSONDecoder().decode(GameProject.self, from: response.data).validated()
        let metadata = recreatedClient.metadata(for: response.taskIdentifier) ?? transfer
        return GenerationProviderOutput(project: project, backgroundTransfers: [Self.metadata(for: metadata)])
    }

    func acknowledge(_ output: GenerationProviderOutput) async throws {
        let recreatedClient = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        for transfer in output.backgroundTransfers {
            try recreatedClient.acknowledgeTransfer(taskIdentifier: transfer.taskIdentifier)
            lock.withLock { acknowledged.append(transfer.taskIdentifier) }
        }
    }

    func cancelBackgroundTransfers(for runID: RunID) async throws {
        let recreatedClient = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let identifiers = try await recreatedClient.cancelTransfers(for: runID)
        lock.withLock { cancelled.append(contentsOf: identifiers) }
    }

    func cleanupTerminalTransfers(retaining runIDs: Set<RunID>) throws {
        try BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral)).cleanupTerminalTransfers(retaining: runIDs)
    }

    func acknowledgedTaskIDs() -> [Int] { lock.withLock { acknowledged } }
    func cancelledTaskIDs() -> [Int] { lock.withLock { cancelled } }
    func isWaitingForCompletion() -> Bool { lock.withLock { waitingForCompletion } }
    func didAttemptTransportRecovery() -> Bool { lock.withLock { attemptedTransportRecovery } }

    private static func metadata(for transfer: BackgroundHTTPClient.TransferMetadata) -> BackgroundTransferMetadata {
        let state: BackgroundTransferState = switch transfer.state {
        case .running: .running
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        }
        return BackgroundTransferMetadata(
            taskIdentifier: transfer.taskIdentifier, projectID: transfer.projectID, runID: transfer.runID,
            operationID: transfer.operationID, candidateID: transfer.candidateID, baseRevisionID: transfer.baseRevisionID,
            requestBodyURL: transfer.requestBodyURL.path, responseURL: transfer.responseURL.path, state: state,
            updatedAt: transfer.updatedAt, statusCode: transfer.responseStatus, responseHeaders: transfer.responseHeaders
        )
    }
}

private struct ImmediateProvider: ModelProvider {
    let displayName = "Immediate Test Provider"
    let project: GameProject

    func generateProject(prompt: String) async throws -> GameProject { project }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject { self.project }
}

private final class CheckpointProvider: ModelProvider, @unchecked Sendable {
    let displayName = "Checkpoint Test Provider"
    let project: GameProject
    private let journal: RunJournal
    private let workspace: ProjectWorkspace
    private let lock = NSLock()
    private var sawDurableCheckpoint = false

    init(project: GameProject, journal: RunJournal, workspace: ProjectWorkspace) {
        self.project = project
        self.journal = journal
        self.workspace = workspace
    }

    func generateProject(prompt: String) async throws -> GameProject { project }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject { self.project }

    func generateProjectOutput(request: GenerationRequest) async throws -> GenerationProviderOutput {
        GenerationProviderOutput(
            project: project,
            backgroundTransfers: [BackgroundTransferMetadata(
                taskIdentifier: 901,
                projectID: request.projectID,
                runID: request.runID,
                operationID: request.operationID,
                candidateID: request.candidateID,
                baseRevisionID: request.baseRevisionID,
                state: .completed
            )]
        )
    }

    func acknowledge(_ output: GenerationProviderOutput) async throws {
        guard let transfer = output.backgroundTransfers.first,
              let runID = transfer.runID,
              let candidateID = transfer.candidateID else { return }
        let journalCheckpoint = await journal.hasEvent(.candidateStaged, runID: runID)
        let workspaceCheckpoint = await MainActor.run { (try? self.workspace.load(candidateID: candidateID)) != nil }
        lock.withLock { sawDurableCheckpoint = journalCheckpoint && workspaceCheckpoint }
    }

    func acknowledgementSawDurableCheckpoint() -> Bool { lock.withLock { sawDurableCheckpoint } }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
