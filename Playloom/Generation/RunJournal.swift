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

    func hasEvent(_ kind: GenerationEventKind, runID: RunID) -> Bool {
        document.runs.first { $0.id == runID }?.events.contains { $0.kind == kind } == true
    }

    func backgroundTransfers(for runID: RunID) -> [BackgroundTransferMetadata] {
        document.runs.first { $0.id == runID }?.backgroundTransfers ?? []
    }

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
        if let transfer = event.backgroundTransfer {
            guard let operation = document.runs[index].operations.last,
                  transfer.projectID == document.projectID,
                  transfer.runID == event.runID,
                  transfer.operationID == operation.id,
                  transfer.candidateID == operation.candidateID,
                  transfer.baseRevisionID == operation.baseRevisionID,
                  event.operationID == operation.id,
                  event.candidateID == operation.candidateID else { throw RunJournalError.invalidEvent }
        }
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
              isMatchingTerminalEvent(event, outcome: outcome, run: run) else { throw RunJournalError.invalidEvent }
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
        guard !isTerminal(document.runs[index].lifecycle), transfer.projectID == document.projectID, transfer.runID == id,
              let operation = document.runs[index].operations.last,
              transfer.operationID == operation.id,
              transfer.candidateID == operation.candidateID,
              transfer.baseRevisionID == operation.baseRevisionID else { throw RunJournalError.invalidEvent }
        let previous = document
        if let existing = document.runs[index].backgroundTransfers.firstIndex(where: { $0.taskIdentifier == transfer.taskIdentifier }) {
            document.runs[index].backgroundTransfers[existing] = transfer
        } else {
            document.runs[index].backgroundTransfers.append(transfer)
        }
        do { try persist() } catch { document = previous; throw error }
    }

    /// Atomically turns an active, structurally valid run into a recovery failure.
    /// Recovery uses this for every branch where no safe continuation exists, so a
    /// relaunch cannot leave the journal's active pointer set forever.
    @discardableResult
    func finalizeRecoveryFailure(
        runID: RunID,
        summary: String,
        detail: String,
        stage: GenerationStage? = nil,
        candidateID: CandidateID? = nil,
        operationID: OperationID? = nil,
        retryRound: Int? = nil
    ) throws -> GenerationEvent {
        guard let index = document.runs.firstIndex(where: { $0.id == runID }) else { throw RunJournalError.runNotFound }
        let run = document.runs[index]
        guard document.activeRunID == runID, !isTerminal(run.lifecycle) else { throw RunJournalError.invalidRecoveryState }
        let timestamp = now()
        let outcome = GenerationOutcome(status: .failed, timestamp: timestamp, summary: summary, detail: detail, candidateID: candidateID, durationMilliseconds: nil, usage: nil)
        let event = GenerationEvent(
            id: UUID(), timestamp: timestamp, projectID: run.projectID, runID: run.id,
            candidateID: candidateID, operationID: operationID, baseRevisionID: run.baseRevisionID,
            kind: .failed, lifecycle: .failed, stage: stage ?? run.currentStage, summary: summary, detail: detail,
            check: nil, fileDiff: nil, retryRound: retryRound, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil
        )
        try finalize(outcome, with: event, runID: runID)
        return event
    }

    @discardableResult
    func finalizeRecoveryCancellation(
        runID: RunID,
        detail: String,
        stage: GenerationStage? = nil,
        candidateID: CandidateID? = nil,
        operationID: OperationID? = nil,
        retryRound: Int? = nil
    ) throws -> GenerationEvent {
        guard let index = document.runs.firstIndex(where: { $0.id == runID }) else { throw RunJournalError.runNotFound }
        let run = document.runs[index]
        guard document.activeRunID == runID, !isTerminal(run.lifecycle) else { throw RunJournalError.invalidRecoveryState }
        let timestamp = now()
        let outcome = GenerationOutcome(status: .cancelled, timestamp: timestamp, summary: "Generation stopped", detail: detail, candidateID: candidateID, durationMilliseconds: nil, usage: nil)
        let event = GenerationEvent(
            id: UUID(), timestamp: timestamp, projectID: run.projectID, runID: run.id,
            candidateID: candidateID, operationID: operationID, baseRevisionID: run.baseRevisionID,
            kind: .cancelled, lifecycle: .cancelled, stage: stage ?? run.currentStage, summary: outcome.summary, detail: detail,
            check: nil, fileDiff: nil, retryRound: retryRound, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil
        )
        try finalize(outcome, with: event, runID: runID)
        return event
    }

    /// Creates a terminal placeholder when the active pointer itself outlives
    /// the run record. The stable run ID is retained for an honest replay rather
    /// than silently clearing a corrupted active pointer.
    @discardableResult
    func finalizeMissingActiveRun(summary: String, detail: String) throws -> GenerationEvent? {
        guard let runID = document.activeRunID else { return nil }
        guard !document.runs.contains(where: { $0.id == runID }) else { throw RunJournalError.invalidRecoveryState }
        let timestamp = now()
        let baseRevisionID = document.currentBaseRevisionID ?? BaseRevisionID()
        let created = GenerationEvent(
            id: UUID(), timestamp: timestamp, projectID: document.projectID, runID: runID,
            candidateID: nil, operationID: nil, baseRevisionID: baseRevisionID, kind: .runCreated,
            lifecycle: .foreground, stage: nil, summary: "Run created", detail: nil, check: nil,
            fileDiff: nil, retryRound: nil, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil
        )
        let outcome = GenerationOutcome(status: .failed, timestamp: timestamp, summary: summary, detail: detail, candidateID: nil, durationMilliseconds: nil, usage: nil)
        let failed = GenerationEvent(
            id: UUID(), timestamp: timestamp, projectID: document.projectID, runID: runID,
            candidateID: nil, operationID: nil, baseRevisionID: baseRevisionID, kind: .failed,
            lifecycle: .failed, stage: nil, summary: summary, detail: detail, check: nil,
            fileDiff: nil, retryRound: nil, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil
        )
        let previous = document
        document.runs.append(GenerationRun(projectID: document.projectID, id: runID, createdAt: timestamp, lifecycle: .failed, baseRevisionID: baseRevisionID, plan: nil, operations: [], events: [created, failed], outcome: outcome))
        document.activeRunID = nil
        do { try persist() } catch { document = previous; throw error }
        return failed
    }

    func recoverInFlightRun(as reason: RunRecoveryReason, timestamp: Date? = nil) throws -> RunID? {
        guard let id = document.activeRunID, let run = document.runs.first(where: { $0.id == id }) else { return nil }
        guard ![.cancelled, .failed, .completed].contains(run.lifecycle) else { throw RunJournalError.invalidRecoveryState }
        let lifecycle: RunLifecycle = reason == .osRelaunchInterrupted ? .relaunchedInterrupted : .forceQuitUnknown
        if run.lifecycle == lifecycle { return id }
        try updateLifecycle(lifecycle, runID: id, timestamp: timestamp)
        return id
    }

    /// Repairs a terminal-looking active record in one write. Older or
    /// interrupted writes can leave a terminal lifecycle without an outcome,
    /// or an outcome without the replay event that explains it. A missing
    /// outcome is conservatively converted to failure; an existing outcome is
    /// preserved and gets its matching terminal event appended when needed.
    @discardableResult
    func normalizeTerminalActiveRun(runID: RunID, fallbackSummary: String, fallbackDetail: String) throws -> [GenerationEvent] {
        guard document.activeRunID == runID, let index = document.runs.firstIndex(where: { $0.id == runID }) else {
            throw RunJournalError.invalidRecoveryState
        }
        let previous = document
        let run = document.runs[index]
        let operation = run.operations.last
        var added: [GenerationEvent] = []

        if let outcome = run.outcome {
            document.runs[index].lifecycle = lifecycle(for: outcome.status)
            if !run.events.contains(where: { isMatchingTerminalEvent($0, outcome: outcome, run: run) }) {
                let event = terminalEvent(for: outcome, run: run, operation: operation)
                document.runs[index].events.append(event)
                added.append(event)
            }
        } else {
            let timestamp = now()
            let candidateID = operation?.candidateID
            let status: GenerationOutcomeStatus = run.lifecycle == .cancelled ? .cancelled : .failed
            let summary = status == .cancelled ? "Generation stopped" : fallbackSummary
            let outcome = GenerationOutcome(
                status: status,
                timestamp: timestamp,
                summary: summary,
                detail: fallbackDetail,
                candidateID: candidateID,
                durationMilliseconds: nil,
                usage: nil
            )
            let event = terminalEvent(for: outcome, run: run, operation: operation)
            document.runs[index].outcome = outcome
            document.runs[index].lifecycle = lifecycle(for: status)
            document.runs[index].events.append(event)
            added.append(event)
        }

        document.activeRunID = nil
        do {
            try persist()
        } catch {
            document = previous
            throw error
        }
        return added
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

    private func isMatchingTerminalEvent(_ event: GenerationEvent, outcome: GenerationOutcome, run: GenerationRun? = nil) -> Bool {
        guard event.candidateID == outcome.candidateID else { return false }
        if let run {
            guard event.projectID == run.projectID,
                  event.runID == run.id,
                  event.baseRevisionID == run.baseRevisionID,
                  event.operationID == run.operations.last?.id else { return false }
        }
        return switch outcome.status {
        case .cancelled: event.kind == .cancelled && event.lifecycle == .cancelled
        case .failed: (event.kind == .failed || event.kind == .staleCompletion) && event.lifecycle == .failed
        case .completed: event.kind == .completed && event.lifecycle == .completed
        }
    }

    private func terminalEvent(for outcome: GenerationOutcome, run: GenerationRun, operation: GenerationOperation?) -> GenerationEvent {
        let kind: GenerationEventKind
        let lifecycle: RunLifecycle
        switch outcome.status {
        case .cancelled:
            kind = .cancelled
            lifecycle = .cancelled
        case .failed:
            kind = .failed
            lifecycle = .failed
        case .completed:
            kind = .completed
            lifecycle = .completed
        }
        return GenerationEvent(
            id: UUID(), timestamp: outcome.timestamp, projectID: run.projectID, runID: run.id,
            candidateID: outcome.candidateID, operationID: operation?.id, baseRevisionID: run.baseRevisionID,
            kind: kind, lifecycle: lifecycle, stage: run.currentStage,
            summary: outcome.summary, detail: outcome.detail, check: nil, fileDiff: nil,
            retryRound: operation?.retryRound, durationMilliseconds: outcome.durationMilliseconds,
            usage: outcome.usage, backgroundTransfer: nil
        )
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
