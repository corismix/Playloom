import Foundation

nonisolated struct RunJournalDocument: Codable, Equatable, Sendable {
    let projectID: ProjectID
    var activeRunID: RunID?
    var currentBaseRevisionID: BaseRevisionID?
    var passingProject: PassingProjectMetadata?
    var runs: [GenerationRun]
}

enum RunJournalError: Error, Equatable { case projectMismatch, runNotFound, invalidRecoveryState, invalidEvent }

actor RunJournal {
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var document: RunJournalDocument

    init(fileURL: URL, projectID: ProjectID, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.fileURL = fileURL
        self.now = now
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.document = try JSONDecoder().decode(RunJournalDocument.self, from: Data(contentsOf: fileURL))
            guard self.document.projectID == projectID else { throw RunJournalError.projectMismatch }
        } else {
            self.document = RunJournalDocument(projectID: projectID, activeRunID: nil, currentBaseRevisionID: nil, passingProject: nil, runs: [])
        }
    }

    func snapshot() -> RunJournalDocument { document }

    func run(_ runID: RunID) -> GenerationRun? { document.runs.first { $0.id == runID } }

    func events(for runID: RunID) -> [GenerationEvent] { document.runs.first { $0.id == runID }?.events ?? [] }

    func isActive(_ runID: RunID) -> Bool { document.activeRunID == runID }

    func activeRun() -> GenerationRun? {
        guard let activeRunID = document.activeRunID else { return nil }
        return document.runs.first { $0.id == activeRunID }
    }

    @discardableResult
    func createRun(
        baseRevisionID: BaseRevisionID,
        plan: GenerationPlan? = nil,
        operation: GenerationOperation? = nil,
        runID: RunID = RunID(),
        timestamp: Date? = nil
    ) throws -> RunID {
        guard !document.runs.contains(where: { $0.id == runID }), operation?.baseRevisionID == nil || operation?.baseRevisionID == baseRevisionID else {
            throw RunJournalError.invalidEvent
        }
        let date = timestamp ?? now()
        let previous = document
        var run = GenerationRun(projectID: document.projectID, id: runID, createdAt: date, lifecycle: .foreground, baseRevisionID: baseRevisionID, plan: plan, operations: operation.map { [$0] } ?? [], events: [], outcome: nil, currentStage: operation?.stage)
        run.events.append(GenerationEvent(id: UUID(), timestamp: date, projectID: document.projectID, runID: runID, candidateID: operation?.candidateID, operationID: operation?.id, baseRevisionID: baseRevisionID, kind: .runCreated, lifecycle: .foreground, stage: operation?.stage, summary: "Run created", detail: nil, check: nil, fileDiff: nil, retryRound: operation?.retryRound, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil))
        document.runs.append(run)
        document.activeRunID = runID
        document.currentBaseRevisionID = baseRevisionID
        do { try persist() } catch { document = previous; throw error }
        return runID
    }

    func append(_ event: GenerationEvent) throws {
        guard let index = document.runs.firstIndex(where: { $0.id == event.runID }) else { throw RunJournalError.runNotFound }
        guard event.projectID == document.projectID else { throw RunJournalError.invalidEvent }
        guard event.baseRevisionID == document.runs[index].baseRevisionID else { throw RunJournalError.invalidEvent }
        guard event.lifecycle.map({ !isTerminal($0) }) ?? true else { throw RunJournalError.invalidEvent }
        if document.runs[index].events.contains(where: { $0.id == event.id }) { return }
        let previous = document
        if isTerminal(document.runs[index].lifecycle) { throw RunJournalError.invalidEvent }
        document.runs[index].events.append(event)
        if let lifecycle = event.lifecycle { document.runs[index].lifecycle = lifecycle }
        if let stage = event.stage { document.runs[index].currentStage = stage }
        if let transfer = event.backgroundTransfer,
           !document.runs[index].backgroundTransfers.contains(where: { $0.taskIdentifier == transfer.taskIdentifier }) {
            document.runs[index].backgroundTransfers.append(transfer)
        }
        if let lifecycle = event.lifecycle, isTerminal(lifecycle), document.activeRunID == event.runID {
            document.activeRunID = nil
        }
        do { try persist() } catch { document = previous; throw error }
    }

    func updateLifecycle(_ lifecycle: RunLifecycle, runID: RunID? = nil, timestamp: Date? = nil) throws {
        let id = runID ?? document.activeRunID
        guard let id, let index = document.runs.firstIndex(where: { $0.id == id }) else { throw RunJournalError.runNotFound }
        let run = document.runs[index]
        guard !isTerminal(run.lifecycle), !isTerminal(lifecycle) else { throw RunJournalError.invalidRecoveryState }
        let previous = document
        document.runs[index].lifecycle = lifecycle
        let operation = run.operations.last
        let event = GenerationEvent(id: UUID(), timestamp: timestamp ?? now(), projectID: run.projectID, runID: run.id, candidateID: operation?.candidateID, operationID: operation?.id, baseRevisionID: run.baseRevisionID, kind: .lifecycleChanged, lifecycle: lifecycle, stage: run.currentStage, summary: lifecycleSummary(lifecycle), detail: nil, check: nil, fileDiff: nil, retryRound: operation?.retryRound, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil)
        document.runs[index].events.append(event)
        do { try persist() } catch { document = previous; throw error }
    }

    /// Commits the terminal outcome and its replay event in one journal write.
    /// A crash can therefore leave a run either before finalization or fully
    /// finalized, never with an outcome that the activity stream cannot explain.
    func finalize(_ outcome: GenerationOutcome, with event: GenerationEvent, runID: RunID? = nil, passingProject: PassingProjectMetadata? = nil) throws {
        let id = runID ?? document.activeRunID
        guard let id, let index = document.runs.firstIndex(where: { $0.id == id }) else { throw RunJournalError.runNotFound }
        let run = document.runs[index]
        guard document.activeRunID == id, !isTerminal(run.lifecycle), event.projectID == document.projectID,
              event.runID == id, event.baseRevisionID == run.baseRevisionID,
              isMatchingTerminalEvent(event, outcome: outcome) else { throw RunJournalError.invalidEvent }
        guard !run.events.contains(where: { $0.id == event.id }) else { throw RunJournalError.invalidEvent }
        guard passingProject == nil || (outcome.status == .completed && passingProject?.baseRevisionID == run.baseRevisionID) else { throw RunJournalError.invalidEvent }
        let previous = document

        document.runs[index].outcome = outcome
        document.runs[index].lifecycle = lifecycle(for: outcome.status)
        document.runs[index].events.append(event)
        if let stage = event.stage { document.runs[index].currentStage = stage }
        if let passingProject {
            document.passingProject = passingProject
            document.currentBaseRevisionID = passingProject.baseRevisionID
        }
        document.activeRunID = nil
        do { try persist() } catch { document = previous; throw error }
    }

    func recordBackgroundTransfer(_ transfer: BackgroundTransferMetadata, runID: RunID? = nil) throws {
        let id = runID ?? document.activeRunID
        guard let id, let index = document.runs.firstIndex(where: { $0.id == id }) else { throw RunJournalError.runNotFound }
        guard transfer.projectID == document.projectID, transfer.runID == id else { throw RunJournalError.invalidEvent }
        let previous = document
        if let existing = document.runs[index].backgroundTransfers.firstIndex(where: { $0.taskIdentifier == transfer.taskIdentifier }) {
            document.runs[index].backgroundTransfers[existing] = transfer
        } else {
            document.runs[index].backgroundTransfers.append(transfer)
        }
        do { try persist() } catch { document = previous; throw error }
    }

    func recoverInFlightRun(as reason: RunRecoveryReason, timestamp: Date? = nil) throws -> RunID? {
        guard let id = document.activeRunID, let run = document.runs.first(where: { $0.id == id }) else { return nil }
        guard ![.cancelled, .failed, .completed].contains(run.lifecycle) else { throw RunJournalError.invalidRecoveryState }
        let lifecycle: RunLifecycle = reason == .osRelaunchInterrupted ? .relaunchedInterrupted : .forceQuitUnknown
        if run.lifecycle == lifecycle { return id }
        try updateLifecycle(lifecycle, runID: id, timestamp: timestamp)
        return id
    }

    func setPassingProject(_ metadata: PassingProjectMetadata, currentBaseRevisionID: BaseRevisionID? = nil) throws {
        let previous = document
        document.passingProject = metadata
        document.currentBaseRevisionID = currentBaseRevisionID ?? metadata.baseRevisionID
        do { try persist() } catch { document = previous; throw error }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(document)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func isTerminal(_ lifecycle: RunLifecycle) -> Bool {
        [.cancelled, .failed, .completed].contains(lifecycle)
    }

    private func isMatchingTerminalEvent(_ event: GenerationEvent, outcome: GenerationOutcome) -> Bool {
        switch outcome.status {
        case .cancelled: event.kind == .cancelled && event.lifecycle == .cancelled
        case .failed: (event.kind == .failed || event.kind == .staleCompletion) && event.lifecycle == .failed
        case .completed: event.kind == .completed && event.lifecycle == .completed
        }
    }

    private func lifecycle(for status: GenerationOutcomeStatus) -> RunLifecycle {
        switch status {
        case .cancelled: .cancelled
        case .failed: .failed
        case .completed: .completed
        }
    }

    private func lifecycleSummary(_ lifecycle: RunLifecycle) -> String {
        switch lifecycle {
        case .foreground: "Generation resumed"
        case .suspended: "Generation suspended"
        case .relaunchedInterrupted: "Generation interrupted by relaunch"
        case .forceQuitUnknown: "Generation status unknown after force-quit"
        case .cancelled: "Generation stopped"
        case .failed: "Generation failed"
        case .completed: "Generation completed"
        }
    }
}
