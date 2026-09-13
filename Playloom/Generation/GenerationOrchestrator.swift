import Foundation
import UIKit

nonisolated struct GenerationRunResult: Sendable {
    let runID: RunID
    let status: GenerationOutcomeStatus
    let message: String
    let project: GameProject?

    var succeeded: Bool { status == .completed }
}

/// Owns the generation state machine and makes its app-owned milestones durable
/// before publishing them to the UI. Provider output is intentionally kept out of
/// the event model; only the fact that a response arrived is recorded.
@MainActor
final class GenerationOrchestrator {
    private struct RunContext: Sendable {
        let projectID: ProjectID
        let runID: RunID
        let candidateID: CandidateID
        let operationID: OperationID
        let baseRevisionID: BaseRevisionID
        let kind: GenerationOperationKind
        let request: GenerationRequest
        let startedAt: Date
    }

    let projectID: ProjectID
    let journal: RunJournal

    private let provider: ModelProvider
    private let workspace: ProjectWorkspace
    private let runtimeCheck: @MainActor (GameRuntimeSession) async throws -> RuntimeReport
    private let setIdleTimerDisabled: @MainActor @Sendable (Bool) -> Void

    private(set) var events: [GenerationEvent] = []
    private(set) var project: GameProject?
    private(set) var session: GameRuntimeSession?
    private(set) var candidateSession: GameRuntimeSession?
    private(set) var isWorking = false

    private var eventContinuations: [UUID: AsyncStream<GenerationEvent>.Continuation] = [:]
    private var activeTask: Task<GenerationRunResult, Never>?
    private var activeContext: RunContext?
    private var cancellationRequestedRunID: RunID?
    private var cancellationEventTask: Task<Void, Never>?
    private var isAppActive = true
    private var didAttemptLaunchRecovery = false
    private var busyReservation: UUID?

    init(
        projectID: ProjectID,
        provider: ModelProvider,
        journal: RunJournal,
        workspace: ProjectWorkspace,
        runtimeCheck: @escaping @MainActor (GameRuntimeSession) async throws -> RuntimeReport,
        setIdleTimerDisabled: @escaping @MainActor @Sendable (Bool) -> Void = { disabled in
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    ) {
        self.projectID = projectID
        self.provider = provider
        self.journal = journal
        self.workspace = workspace
        self.runtimeCheck = runtimeCheck
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }

    /// Returns a replayable typed stream. Existing events are yielded before new
    /// events, so a view recreated after suspension does not show a silent gap.
    func eventStream() -> AsyncStream<GenerationEvent> {
        let replay = events
        return AsyncStream { [weak self] continuation in
            let token = UUID()
            replay.forEach { continuation.yield($0) }
            self?.eventContinuations[token] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.eventContinuations.removeValue(forKey: token)
                }
            }
        }
    }

    func loadPersistedActivity() async {
        let snapshot = await journal.snapshot()
        if let passing = loadPassingProject(from: snapshot) {
            project = passing.project
        }
        guard let run = snapshot.runs.last else { return }
        await refreshEvents(for: run.id)
    }

    func startGenerate(prompt: String) async -> Task<GenerationRunResult, Never> {
        await start(kind: .generate, prompt: prompt, instruction: nil, currentProject: nil)
    }

    func startEdit(project: GameProject, instruction: String) async -> Task<GenerationRunResult, Never> {
        await start(kind: .edit, prompt: instruction, instruction: instruction, currentProject: project)
    }

    func cancel() {
        guard let context = activeContext, isWorking else { return }
        guard cancellationRequestedRunID != context.runID else { return }
        cancellationRequestedRunID = context.runID
        let event = makeEvent(
            context: context,
            kind: .cancellationRequested,
            lifecycle: .foreground,
            stage: currentStage,
            summary: "Stopping generation",
            detail: "The active provider request is being cancelled."
        )
        cancellationEventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.appendAndPublish(event)
        }
        activeTask?.cancel()
    }

    func didEnterBackground() {
        isAppActive = false
        setIdleTimerDisabled(false)
        guard isWorking, let context = activeContext else { return }
        Task { @MainActor [weak self] in
            guard let self, self.activeContext?.runID == context.runID else { return }
            let lifecycle = self.makeEvent(
                context: context,
                kind: .lifecycleChanged,
                lifecycle: .suspended,
                stage: self.currentStage,
                summary: "Generation suspended",
                detail: "Playloom will validate the candidate when you return."
            )
            try? await self.appendAndPublish(lifecycle)
            if !self.provider.supportsBackgroundContinuation {
                let warning = self.makeEvent(
                    context: context,
                    kind: .keepOpenWarning,
                    lifecycle: .suspended,
                    stage: self.currentStage,
                    summary: "Keep Playloom open",
                    detail: "\(self.provider.displayName) cannot continue this request after the app is closed."
                )
                try? await self.appendAndPublish(warning)
            }
        }
    }

    func didBecomeActive() {
        isAppActive = true
        guard isWorking, let context = activeContext else { return }
        setIdleTimerDisabled(true)
        Task { @MainActor [weak self] in
            guard let self, self.activeContext?.runID == context.runID else { return }
            let lifecycle = self.makeEvent(
                context: context,
                kind: .lifecycleChanged,
                lifecycle: .foreground,
                stage: self.currentStage,
                summary: "Generation resumed",
                detail: "Playloom is ready to continue the current run."
            )
            try? await self.appendAndPublish(lifecycle)
        }
    }

    /// Marks a journaled in-flight run explicitly. The caller chooses the reason:
    /// a background-session OS relaunch is different from an ordinary launch after
    /// a user force-quit, and the activity card must not conflate them.
    func recoverOnLaunch(as reason: RunRecoveryReason) async {
        guard !didAttemptLaunchRecovery, !isWorking, busyReservation == nil else { return }
        didAttemptLaunchRecovery = true
        let reservation = UUID()
        busyReservation = reservation
        defer {
            if busyReservation == reservation { busyReservation = nil }
        }

        let snapshot = await journal.snapshot()
        cleanupTerminalTransport(retaining: snapshot.activeRunID.map { Set([$0]) } ?? [])
        guard let runID = snapshot.activeRunID else {
            if let latest = snapshot.runs.last { await refreshEvents(for: latest.id) }
            return
        }
        guard let snapshotRun = snapshot.runs.first(where: { $0.id == runID }) else {
            do {
                _ = try await journal.finalizeMissingActiveRun(
                    summary: "Generation recovery failed",
                    detail: recoveryDetail(reason: reason, issue: "The journal active run record was missing; the last playable game was preserved.")
                )
                await refreshEvents(for: runID)
                cleanupTerminalTransport()
            } catch {
                didAttemptLaunchRecovery = false
            }
            return
        }

        if [.cancelled, .failed, .completed].contains(snapshotRun.lifecycle) || snapshotRun.outcome != nil {
            if let recoveringProvider = provider as? any BackgroundRecoveringProvider {
                try? await recoveringProvider.cancelBackgroundTransfers(for: runID)
            }
            do {
                _ = try await journal.normalizeTerminalActiveRun(
                    runID: runID,
                    fallbackSummary: "Generation recovery failed",
                    fallbackDetail: recoveryDetail(reason: reason, issue: "The terminal run record was incomplete; the last playable game was preserved.")
                )
                await refreshEvents(for: runID)
                cleanupTerminalTransport()
            } catch {
                didAttemptLaunchRecovery = false
            }
            return
        }

        do {
            _ = try await journal.recoverInFlightRun(as: reason)
        } catch {
            await finishRecoveryFailure(
                run: snapshotRun,
                summary: "Generation recovery failed",
                detail: recoveryDetail(reason: reason, issue: "The interrupted run could not be classified safely; the last playable game was preserved.")
            )
            return
        }
        await refreshEvents(for: runID)

        guard busyReservation == reservation, let run = await journal.run(runID) else {
            await finishRecoveryFailure(
                run: snapshotRun,
                summary: "Generation recovery failed",
                detail: recoveryDetail(reason: reason, issue: "The interrupted run was no longer available to resume; the last playable game was preserved.")
            )
            return
        }
        guard let operation = run.operations.last, let candidateID = operation.candidateID else {
            await finishRecoveryFailure(
                run: run,
                summary: "Generation could not resume",
                detail: recoveryDetail(reason: reason, issue: "The interrupted run did not retain a stable candidate identity; the last playable game was preserved.")
            )
            return
        }

        if run.events.contains(where: { $0.kind == .cancellationRequested }) {
            if let recoveringProvider = provider as? any BackgroundRecoveringProvider {
                try? await recoveringProvider.cancelBackgroundTransfers(for: runID)
            }
            await finishRecoveryCancellation(run: run, operation: operation, reason: reason)
            return
        }

        let currentSnapshot = await journal.snapshot()
        let restoredCurrent = loadPassingProject(from: currentSnapshot)
        if operation.kind == .edit {
            guard let restoredCurrent, let passing = currentSnapshot.passingProject,
                  passing.baseRevisionID == operation.baseRevisionID else {
                await finishRecoveryFailure(
                    run: run,
                    summary: "Generation could not resume",
                    detail: recoveryDetail(reason: reason, issue: "The current project for this edit was not available at its recorded base; the last playable game was preserved."),
                    stage: .planning,
                    candidateID: candidateID,
                    operationID: operation.id,
                    retryRound: operation.retryRound
                )
                return
            }
            project = restoredCurrent.project
        }

        let journalTransfers = run.backgroundTransfers
        guard journalTransfers.allSatisfy({ transferMatches($0, run: run, operation: operation) }) else {
            await finishRecoveryFailure(
                run: run,
                summary: "Background response rejected",
                detail: recoveryDetail(reason: reason, issue: "A recorded provider transfer did not match this project's operation, candidate, or base identity."),
                stage: .receiving,
                candidateID: candidateID,
                operationID: operation.id,
                retryRound: operation.retryRound
            )
            return
        }

        let stagedCandidate: ProjectWorkspace.StagedProject?
        if run.events.contains(where: { $0.kind == .candidateStaged }) {
            do {
                stagedCandidate = try workspace.load(candidateID: candidateID)
            } catch {
                await finishRecoveryFailure(
                    run: run,
                    summary: "Staged candidate unavailable",
                    detail: recoveryDetail(reason: reason, issue: "The durable candidate checkpoint could not be reopened; the last playable game was preserved."),
                    stage: .staging,
                    candidateID: candidateID,
                    operationID: operation.id,
                    retryRound: operation.retryRound
                )
                return
            }
        } else {
            stagedCandidate = nil
        }

        let selectedTransfer: BackgroundHTTPClient.TransferMetadata?
        if stagedCandidate != nil {
            selectedTransfer = nil
        } else {
            guard provider.supportsBackgroundContinuation,
                  let recoveringProvider = provider as? any BackgroundRecoveringProvider,
                  recoveringProvider.supportsBackgroundRecovery else {
                await finishRecoveryFailure(
                    run: run,
                    summary: "Background response unavailable",
                    detail: recoveryDetail(reason: reason, issue: "This provider cannot reattach the interrupted request; the last playable game was preserved."),
                    stage: .receiving,
                    candidateID: candidateID,
                    operationID: operation.id,
                    retryRound: operation.retryRound
                )
                return
            }

            let transfers: [BackgroundHTTPClient.TransferMetadata]
            do {
                transfers = try await recoveringProvider.recoverBackgroundTransfers(for: runID)
            } catch {
                await finishRecoveryFailure(
                    run: run,
                    summary: "Background response unavailable",
                    detail: recoveryDetail(reason: reason, issue: "The background provider response could not be recovered safely; the last playable game was preserved."),
                    stage: .receiving,
                    candidateID: candidateID,
                    operationID: operation.id,
                    retryRound: operation.retryRound
                )
                return
            }
            guard transfers.allSatisfy({ transferMatches($0, run: run, operation: operation) }) else {
                await finishRecoveryFailure(
                    run: run,
                    summary: "Background response rejected",
                    detail: recoveryDetail(reason: reason, issue: "A recovered provider transfer did not match this project's operation, candidate, or base identity."),
                    stage: .receiving,
                    candidateID: candidateID,
                    operationID: operation.id,
                    retryRound: operation.retryRound
                )
                return
            }
            do {
                for transfer in transfers { try await journal.recordBackgroundTransfer(appMetadata(for: transfer), runID: runID) }
            } catch {
                await finishRecoveryFailure(
                    run: run,
                    summary: "Background response unavailable",
                    detail: recoveryDetail(reason: reason, issue: "The recovered transfer state could not be recorded durably; the last playable game was preserved."),
                    stage: .receiving,
                    candidateID: candidateID,
                    operationID: operation.id,
                    retryRound: operation.retryRound
                )
                return
            }
            guard let eligible = transfers.last(where: { $0.state == .running || $0.state == .completed }) else {
                await finishRecoveryWithoutTransfer(run: run, reason: reason, transfers: transfers, operation: operation)
                return
            }
            selectedTransfer = eligible
        }

        guard busyReservation == reservation else {
            await finishRecoveryFailure(
                run: run,
                summary: "Generation recovery failed",
                detail: recoveryDetail(reason: reason, issue: "The interrupted run lost recovery ownership; the last playable game was preserved."),
                stage: .receiving,
                candidateID: candidateID,
                operationID: operation.id,
                retryRound: operation.retryRound
            )
            return
        }

        let recoveryLifecycle: RunLifecycle = isAppActive ? .foreground : .suspended
        let recoverySummary = isAppActive ? "Generation resumed" : "Background response recovered"
        let recoveryDetailText = isAppActive
            ? "The background provider response is being recovered in the foreground."
            : "The response is retained until Playloom returns to the foreground for validation."
        let resumed = GenerationEvent(
            id: UUID(), timestamp: Date(), projectID: run.projectID, runID: run.id,
            candidateID: candidateID, operationID: operation.id, baseRevisionID: operation.baseRevisionID,
            kind: .lifecycleChanged, lifecycle: recoveryLifecycle, stage: stagedCandidate == nil ? .receiving : .staging,
            summary: recoverySummary, detail: recoveryDetailText,
            check: nil, fileDiff: nil, retryRound: operation.retryRound, durationMilliseconds: nil, usage: nil, backgroundTransfer: nil
        )
        do {
            try await appendAndPublish(resumed)
        } catch {
            await finishRecoveryFailure(
                run: run,
                summary: "Generation recovery failed",
                detail: recoveryDetail(reason: reason, issue: "The recovery checkpoint could not be recorded; the last playable game was preserved."),
                stage: .receiving,
                candidateID: candidateID,
                operationID: operation.id,
                retryRound: operation.retryRound
            )
            return
        }

        let context = RunContext(
            projectID: run.projectID,
            runID: run.id,
            candidateID: candidateID,
            operationID: operation.id,
            baseRevisionID: operation.baseRevisionID,
            kind: operation.kind,
            request: GenerationRequest(operation: operation.kind, projectID: run.projectID, runID: run.id, candidateID: candidateID, operationID: operation.id, baseRevisionID: operation.baseRevisionID, prompt: ""),
            startedAt: run.createdAt
        )
        activeContext = context
        isWorking = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return GenerationRunResult(runID: run.id, status: .failed, message: "Generation coordinator unavailable.", project: nil) }
            return await self.perform(
                context: context,
                currentProject: restoredCurrent?.project,
                recoveredTransfer: selectedTransfer,
                recoveredCandidate: stagedCandidate,
                recoveredTransfers: journalTransfers
            )
        }
        activeTask = task
    }

    private func start(
        kind: GenerationOperationKind,
        prompt: String,
        instruction: String?,
        currentProject: GameProject?
    ) async -> Task<GenerationRunResult, Never> {
        if isWorking || busyReservation != nil {
            return Task {
                GenerationRunResult(runID: RunID(), status: .failed, message: "Another generation is already running.", project: nil)
            }
        }

        let reservation = UUID()
        busyReservation = reservation
        defer {
            if busyReservation == reservation { busyReservation = nil }
        }
        let snapshot = await journal.snapshot()
        let baseRevisionID = snapshot.currentBaseRevisionID ?? BaseRevisionID()
        let runID = RunID()
        let candidateID = CandidateID()
        let operationID = OperationID()
        let operation = GenerationOperation(
            id: operationID,
            kind: kind,
            stage: .planning,
            candidateID: candidateID,
            baseRevisionID: baseRevisionID,
            retryRound: nil
        )
        let request = GenerationRequest(
            operation: kind,
            projectID: projectID,
            runID: runID,
            candidateID: candidateID,
            operationID: operationID,
            baseRevisionID: baseRevisionID,
            prompt: prompt,
            instruction: instruction
        )
        let context = RunContext(
            projectID: projectID,
            runID: runID,
            candidateID: candidateID,
            operationID: operationID,
            baseRevisionID: baseRevisionID,
            kind: kind,
            request: request,
            startedAt: Date()
        )

        do {
            _ = try await journal.createRun(baseRevisionID: baseRevisionID, operation: operation, runID: runID)
            guard busyReservation == reservation else {
                await finishRecoveryFailure(
                    run: await journal.run(runID) ?? GenerationRun(
                        projectID: projectID, id: runID, createdAt: context.startedAt, lifecycle: .foreground,
                        baseRevisionID: baseRevisionID, plan: nil, operations: [operation], events: [], outcome: nil
                    ),
                    summary: "Generation could not start",
                    detail: "The durable run lost ownership before provider work began; the last playable game was preserved.",
                    stage: .planning,
                    candidateID: candidateID,
                    operationID: operationID
                )
                return Task { GenerationRunResult(runID: runID, status: .failed, message: "Generation ownership changed before the run started.", project: nil) }
            }
            activeContext = context
            isWorking = true
            cancellationRequestedRunID = nil
            await refreshEvents(for: runID)
        } catch {
            return Task {
                GenerationRunResult(runID: runID, status: .failed, message: "Could not start a durable generation run.", project: nil)
            }
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return GenerationRunResult(runID: context.runID, status: .failed, message: "Generation coordinator unavailable.", project: nil)
            }
            return await self.perform(context: context, currentProject: currentProject)
        }
        activeTask = task
        return task
    }

    private func perform(
        context: RunContext,
        currentProject: GameProject?,
        recoveredTransfer: BackgroundHTTPClient.TransferMetadata? = nil,
        recoveredCandidate: ProjectWorkspace.StagedProject? = nil,
        recoveredTransfers: [BackgroundTransferMetadata] = []
    ) async -> GenerationRunResult {
        if isAppActive { setIdleTimerDisabled(true) }
        defer {
            setIdleTimerDisabled(false)
            if activeContext?.runID == context.runID {
                activeContext = nil
                activeTask = nil
                isWorking = false
                candidateSession = nil
                cancellationRequestedRunID = nil
                cancellationEventTask = nil
            }
        }

        do {
            try Task.checkCancellation()
            let output: GenerationProviderOutput
            if let recoveredCandidate {
                output = GenerationProviderOutput(project: recoveredCandidate.project, backgroundTransfers: recoveredTransfers)
            } else if let recoveredTransfer {
                try await emit(context: context, kind: .stageStarted, stage: .receiving, summary: "Reattaching provider response", detail: "Recovering the response delivered by the background transfer.")
                guard let recoveringProvider = provider as? any BackgroundRecoveringProvider else { throw OrchestratorError.unrecoverableTransfer }
                output = try await recoveringProvider.recoverProjectOutput(from: recoveredTransfer)
            } else {
                try await emit(context: context, kind: .stageStarted, stage: .planning, summary: "Preparing generation", detail: "Recording the run before contacting the provider.")
                try await emit(context: context, kind: .stageFinished, stage: .planning, summary: "Generation prepared", detail: "The run has stable project, operation, candidate, and base IDs.")
                try Task.checkCancellation()

                try await emit(context: context, kind: .stageStarted, stage: .generating, summary: "Generating your game", detail: "Contacting \(provider.displayName).")
                switch context.kind {
                case .generate:
                    output = try await provider.generateProjectOutput(request: context.request)
                case .edit:
                    guard let currentProject else { throw OrchestratorError.missingProject }
                    output = try await provider.editProjectOutput(currentProject, request: context.request)
                }
            }
            let candidate = output.project
            try Task.checkCancellation()
            guard output.backgroundTransfers.allSatisfy({ transferMatches($0, context: context) }) else { throw OrchestratorError.transferIdentityMismatch }
            if output.backgroundTransfers.isEmpty {
                try await emit(context: context, kind: .providerOutputReceived, stage: .receiving, summary: recoveredTransfer == nil ? "Generation response received" : "Background response recovered", detail: "Playloom received a candidate from the provider.")
            } else {
                for transfer in output.backgroundTransfers {
                    try await journal.recordBackgroundTransfer(transfer, runID: context.runID)
                    try await emit(context: context, kind: .providerOutputReceived, stage: .receiving, summary: recoveredTransfer == nil ? "Generation response received" : "Background response recovered", detail: "Playloom received a candidate from the provider.", backgroundTransfer: transfer)
                }
            }

            try await waitForForegroundIfNeeded()
            try Task.checkCancellation()

            try await emit(context: context, kind: .stageStarted, stage: .staging, summary: "Staging generated files", detail: "Checking project structure and copying the local Phaser runtime.")
            let directory: URL
            if let recoveredCandidate {
                directory = recoveredCandidate.directory
                try await emit(context: context, kind: .stageFinished, stage: .staging, summary: "Candidate restored", detail: "The durable candidate checkpoint is being reused.")
            } else {
                directory = try workspace.stage(candidate, candidateID: context.candidateID)
                try await emit(context: context, kind: .candidateStaged, stage: .staging, summary: "Candidate staged", detail: "The candidate is isolated from the last playable game.", fileDiff: fileDiff(from: currentProject, to: candidate))
            }
            try await provider.acknowledge(output)
            try await emit(context: context, kind: .stageFinished, stage: .staging, summary: "Files staged", detail: "The candidate is ready for a sandboxed runtime check.")

            try await emit(context: context, kind: .stageStarted, stage: .launching, summary: "Starting game runtime", detail: "Loading the candidate in a sandboxed WebKit view.")
            let checkingSession = GameRuntimeSession(projectDirectory: directory)
            candidateSession = checkingSession
            _ = checkingSession.makeWebView()
            try await emit(context: context, kind: .stageFinished, stage: .launching, summary: "Game runtime started", detail: "The candidate is loaded in its isolated WebKit view.")

            try await waitForForegroundIfNeeded()
            setIdleTimerDisabled(true)
            try await emit(context: context, kind: .stageStarted, stage: .checking, summary: "Checking playable candidate", detail: "Running Playloom's bridge, load, canvas, heartbeat, input, and restart checks.")
            await Task.yield()
            let report = try await runtimeCheck(checkingSession)
            try Task.checkCancellation()
            try await emitCheckEvents(context: context, report: report)
            try await emit(context: context, kind: .stageFinished, stage: .checking, summary: report.isPassing ? "Basic runtime passed" : "Candidate checks finished", detail: report.isPassing ? "The universal runtime checks passed." : "The candidate did not pass all required runtime checks.")

            guard report.isPassing else {
                await finishFailure(context: context, summary: "Candidate rejected", detail: "The last playable game was preserved.")
                return GenerationRunResult(runID: context.runID, status: .failed, message: "Candidate rejected. The last playable game was preserved.", project: nil)
            }

            try Task.checkCancellation()
            guard cancellationRequestedRunID != context.runID else { throw CancellationError() }
            guard await journal.isActive(context.runID) else {
                await finishStale(context: context)
                return GenerationRunResult(runID: context.runID, status: .failed, message: "A newer run owns this project.", project: nil)
            }
            try Task.checkCancellation()
            guard cancellationRequestedRunID != context.runID else { throw CancellationError() }
        let metadata = PassingProjectMetadata(baseRevisionID: context.baseRevisionID, candidateID: context.candidateID, title: candidate.title, filePaths: candidate.files.keys.sorted(), updatedAt: Date())
            try Task.checkCancellation()
            guard cancellationRequestedRunID != context.runID else { throw CancellationError() }
            guard await journal.isActive(context.runID) else {
                await finishStale(context: context)
                return GenerationRunResult(runID: context.runID, status: .failed, message: "A newer run owns this project.", project: nil)
            }
            try await finishSuccess(context: context, report: report, passingProject: metadata)
            project = candidate
            session = checkingSession
            candidateSession = nil
            return GenerationRunResult(runID: context.runID, status: .completed, message: "Playable", project: candidate)
        } catch is CancellationError {
            await finishCancellation(context: context)
            return GenerationRunResult(runID: context.runID, status: .cancelled, message: "Generation stopped. The last playable game was preserved.", project: nil)
        } catch {
            if Task.isCancelled || cancellationRequestedRunID == context.runID {
                await finishCancellation(context: context)
                return GenerationRunResult(runID: context.runID, status: .cancelled, message: "Generation stopped. The last playable game was preserved.", project: nil)
            }
            await finishFailure(context: context, summary: "Generation failed", detail: safeFailureMessage(for: error))
            return GenerationRunResult(runID: context.runID, status: .failed, message: safeFailureMessage(for: error), project: nil)
        }
    }

    private func emitCheckEvents(context: RunContext, report: RuntimeReport) async throws {
        for label in report.passed {
            let check = GenerationCheckResult(kind: checkKind(for: label), status: .passed, summary: label, detail: nil, durationMilliseconds: nil)
            try await emit(context: context, kind: .checkFinished, stage: .checking, summary: label, detail: nil, check: check)
        }
        for label in report.failures {
            let check = GenerationCheckResult(kind: checkKind(for: label), status: .failed, summary: checkSummary(for: label), detail: nil, durationMilliseconds: nil)
            try await emit(context: context, kind: .checkFinished, stage: .checking, summary: check.summary, detail: "This required check did not pass.", check: check)
        }
    }

    private func waitForForegroundIfNeeded() async throws {
        while !isAppActive {
            try Task.checkCancellation()
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
    }

    private func finishSuccess(context: RunContext, report: RuntimeReport, passingProject: PassingProjectMetadata) async throws {
        let duration = milliseconds(since: context.startedAt)
        let outcome = GenerationOutcome(status: .completed, timestamp: Date(), summary: "Playable", detail: "Basic runtime passed.", candidateID: context.candidateID, durationMilliseconds: duration, usage: nil)
        let event = makeEvent(context: context, kind: .completed, lifecycle: .completed, stage: .checking, summary: "Playable", detail: "Basic runtime passed.", durationMilliseconds: duration)
        try await journal.finalize(outcome, with: event, runID: context.runID, passingProject: passingProject)
        publish(event)
        cleanupTerminalTransport()
        _ = report
    }

    private func finishFailure(context: RunContext, summary: String, detail: String) async {
        let duration = milliseconds(since: context.startedAt)
        let outcome = GenerationOutcome(status: .failed, timestamp: Date(), summary: summary, detail: detail, candidateID: context.candidateID, durationMilliseconds: duration, usage: nil)
        let event = makeEvent(context: context, kind: .failed, lifecycle: .failed, stage: currentStage, summary: summary, detail: detail, durationMilliseconds: duration)
        do {
            try await journal.finalize(outcome, with: event, runID: context.runID)
            publish(event)
            cleanupTerminalTransport()
        } catch {
            // The in-memory result remains truthful if the journal itself cannot
            // be written; do not add an unpersisted second status message.
        }
    }

    private func finishCancelled(context: RunContext) async {
        let duration = milliseconds(since: context.startedAt)
        let detail = "The last playable game was preserved."
        let outcome = GenerationOutcome(status: .cancelled, timestamp: Date(), summary: "Generation stopped", detail: detail, candidateID: context.candidateID, durationMilliseconds: duration, usage: nil)
        let event = makeEvent(context: context, kind: .cancelled, lifecycle: .cancelled, stage: currentStage, summary: "Generation stopped", detail: detail, durationMilliseconds: duration)
        do {
            try await journal.finalize(outcome, with: event, runID: context.runID)
            publish(event)
            cleanupTerminalTransport()
        } catch {
            // The cancellation result is still honest in memory if persistence
            // fails; the next launch will show the interrupted journal state.
        }
    }

    private func finishCancellation(context: RunContext) async {
        if let cancellationEventTask {
            await cancellationEventTask.value
            self.cancellationEventTask = nil
        }
        await finishCancelled(context: context)
    }

    private func finishStale(context: RunContext) async {
        let detail = "A newer run owns the current project; this result was ignored."
        let outcome = GenerationOutcome(status: .failed, timestamp: Date(), summary: "Stale result ignored", detail: detail, candidateID: context.candidateID, durationMilliseconds: milliseconds(since: context.startedAt), usage: nil)
        let event = makeEvent(context: context, kind: .staleCompletion, lifecycle: .failed, stage: currentStage, summary: "Stale result ignored", detail: detail, durationMilliseconds: outcome.durationMilliseconds)
        do {
            try await journal.finalize(outcome, with: event, runID: context.runID)
            publish(event)
            cleanupTerminalTransport()
        } catch {
            // A newer run already owns the project; there is no safe promotion.
        }
    }

    private func emit(
        context: RunContext,
        kind: GenerationEventKind,
        lifecycle: RunLifecycle? = nil,
        stage: GenerationStage? = nil,
        summary: String,
        detail: String?,
        check: GenerationCheckResult? = nil,
        fileDiff: FileDiffSummary? = nil,
        durationMilliseconds: Int? = nil,
        backgroundTransfer: BackgroundTransferMetadata? = nil
    ) async throws {
        let event = makeEvent(context: context, kind: kind, lifecycle: lifecycle, stage: stage, summary: summary, detail: detail, check: check, fileDiff: fileDiff, durationMilliseconds: durationMilliseconds, backgroundTransfer: backgroundTransfer)
        try await appendAndPublish(event)
    }

    private func makeEvent(
        context: RunContext,
        kind: GenerationEventKind,
        lifecycle: RunLifecycle?,
        stage: GenerationStage?,
        summary: String,
        detail: String?,
        check: GenerationCheckResult? = nil,
        fileDiff: FileDiffSummary? = nil,
        durationMilliseconds: Int? = nil,
        backgroundTransfer: BackgroundTransferMetadata? = nil
    ) -> GenerationEvent {
        GenerationEvent(
            id: UUID(), timestamp: Date(), projectID: context.projectID, runID: context.runID,
            candidateID: context.candidateID, operationID: context.operationID, baseRevisionID: context.baseRevisionID,
            kind: kind, lifecycle: lifecycle, stage: stage, summary: summary, detail: detail, check: check,
            fileDiff: fileDiff, retryRound: nil, durationMilliseconds: durationMilliseconds, usage: nil, backgroundTransfer: backgroundTransfer
        )
    }

    private func finishRecoveryFailure(
        run: GenerationRun,
        summary: String,
        detail: String,
        stage: GenerationStage? = nil,
        candidateID: CandidateID? = nil,
        operationID: OperationID? = nil,
        retryRound: Int? = nil
    ) async {
        do {
            let event = try await journal.finalizeRecoveryFailure(
                runID: run.id,
                summary: summary,
                detail: detail,
                stage: stage,
                candidateID: candidateID ?? run.operations.last?.candidateID,
                operationID: operationID ?? run.operations.last?.id,
                retryRound: retryRound ?? run.operations.last?.retryRound
            )
            publish(event)
            cleanupTerminalTransport()
        } catch {
            // A failed disk write cannot be made terminal in memory. Leave the
            // active journal intact for a later launch and allow a retry rather
            // than claiming that recovery completed.
            didAttemptLaunchRecovery = false
            await refreshEvents(for: run.id)
        }
    }

    private func finishRecoveryCancellation(run: GenerationRun, operation: GenerationOperation, reason: RunRecoveryReason) async {
        let detail = recoveryDetail(reason: reason, issue: "Stop was requested before the interrupted provider response could be recovered; the last playable game was preserved.")
        do {
            let event = try await journal.finalizeRecoveryCancellation(
                runID: run.id,
                detail: detail,
                stage: run.currentStage,
                candidateID: operation.candidateID,
                operationID: operation.id,
                retryRound: operation.retryRound
            )
            publish(event)
            cleanupTerminalTransport()
        } catch {
            didAttemptLaunchRecovery = false
            await refreshEvents(for: run.id)
        }
    }

    private func finishRecoveryWithoutTransfer(
        run: GenerationRun,
        reason: RunRecoveryReason,
        transfers: [BackgroundHTTPClient.TransferMetadata],
        operation: GenerationOperation
    ) async {
        let states = Set(transfers.map(\.state))
        let stopWasRequested = run.events.contains { $0.kind == .cancellationRequested }
        if stopWasRequested && states == [.cancelled] {
            await finishRecoveryCancellation(run: run, operation: operation, reason: reason)
            return
        }

        let summary: String
        let issue: String
        if transfers.isEmpty {
            summary = "Recovery could not find a response"
            issue = "No background provider transfer was recorded for the active run."
        } else if states == [.failed] {
            summary = "Background response failed"
            issue = "The recorded background provider transfer failed before recovery."
        } else if states == [.interrupted] {
            summary = "Background response interrupted"
            issue = "The recorded background provider transfer was interrupted before it could be reattached."
        } else if states == [.cancelled] {
            summary = "Background response cancelled"
            issue = "The recorded background provider transfer was cancelled before recovery without a durable Stop request."
        } else {
            summary = "Background response unavailable"
            issue = "Every recorded background provider transfer was failed, cancelled, or interrupted."
        }
        await finishRecoveryFailure(
            run: run,
            summary: summary,
            detail: recoveryDetail(reason: reason, issue: "\(issue) The last playable game was preserved."),
            stage: .receiving,
            candidateID: operation.candidateID,
            operationID: operation.id,
            retryRound: operation.retryRound
        )
    }

    private func recoveryDetail(reason: RunRecoveryReason, issue: String) -> String {
        let lifecycle = switch reason {
        case .osRelaunchInterrupted: "The operating system relaunched Playloom after interrupting this run."
        case .forceQuitUnknown: "Playloom was relaunched after a force-quit, so continuation of this run cannot be confirmed."
        }
        return "\(lifecycle) \(issue)"
    }

    private func transferMatches(_ transfer: BackgroundTransferMetadata, run: GenerationRun, operation: GenerationOperation) -> Bool {
        transfer.projectID == run.projectID && transfer.runID == run.id && transfer.operationID == operation.id
            && transfer.candidateID == operation.candidateID && transfer.baseRevisionID == operation.baseRevisionID
    }

    private func transferMatches(_ transfer: BackgroundHTTPClient.TransferMetadata, run: GenerationRun, operation: GenerationOperation) -> Bool {
        transfer.projectID == run.projectID && transfer.runID == run.id && transfer.operationID == operation.id
            && transfer.candidateID == operation.candidateID && transfer.baseRevisionID == operation.baseRevisionID
    }

    private func transferMatches(_ transfer: BackgroundTransferMetadata, context: RunContext) -> Bool {
        transfer.projectID == context.projectID && transfer.runID == context.runID && transfer.operationID == context.operationID
            && transfer.candidateID == context.candidateID && transfer.baseRevisionID == context.baseRevisionID
    }

    private func loadPassingProject(from snapshot: RunJournalDocument) -> ProjectWorkspace.StagedProject? {
        guard let metadata = snapshot.passingProject, let candidateID = metadata.candidateID,
              let staged = try? workspace.load(candidateID: candidateID), staged.project.title == metadata.title else { return nil }
        return staged
    }

    private func cleanupTerminalTransport(retaining runIDs: Set<RunID> = []) {
        guard let recoveringProvider = provider as? any BackgroundRecoveringProvider else { return }
        try? recoveringProvider.cleanupTerminalTransfers(retaining: runIDs)
    }

    private func appMetadata(for transfer: BackgroundHTTPClient.TransferMetadata) -> BackgroundTransferMetadata {
        let state: BackgroundTransferState = switch transfer.state {
        case .running: .running
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        }
        return BackgroundTransferMetadata(
            taskIdentifier: transfer.taskIdentifier,
            projectID: transfer.projectID,
            runID: transfer.runID,
            operationID: transfer.operationID,
            candidateID: transfer.candidateID,
            baseRevisionID: transfer.baseRevisionID,
            requestBodyURL: transfer.requestBodyURL.path,
            responseURL: transfer.responseURL.path,
            state: state,
            updatedAt: transfer.updatedAt,
            statusCode: transfer.responseStatus,
            responseHeaders: transfer.responseHeaders
        )
    }

    private func appendAndPublish(_ event: GenerationEvent) async throws {
        try await journal.append(event)
        publish(event)
    }

    private func refreshEvents(for runID: RunID) async {
        let persisted = await journal.events(for: runID)
        let known = Set(events.map(\.id))
        for event in persisted where !known.contains(event.id) {
            events.append(event)
            eventContinuations.values.forEach { $0.yield(event) }
        }
    }

    private func publish(_ event: GenerationEvent) {
        events.append(event)
        eventContinuations.values.forEach { $0.yield(event) }
    }

    private var currentStage: GenerationStage? {
        events.last(where: { $0.runID == activeContext?.runID && $0.stage != nil })?.stage
    }

    private func fileDiff(from old: GameProject?, to new: GameProject) -> FileDiffSummary {
        let oldFiles = old?.files ?? [:]
        let oldPaths = Set(oldFiles.keys)
        let newPaths = Set(new.files.keys)
        let added = newPaths.subtracting(oldPaths).sorted()
        let removed = oldPaths.subtracting(newPaths).sorted()
        let changed = newPaths.intersection(oldPaths).filter { oldFiles[$0] != new.files[$0] }.sorted()
        return FileDiffSummary(added: added, changed: changed, removed: removed, totalBytes: new.files.values.reduce(0) { $0 + $1.utf8.count })
    }

    private func checkKind(for label: String) -> GenerationCheckKind {
        let value = label.lowercased()
        if value.contains("bridge") { return .bridge }
        if value.contains("load") { return .load }
        if value.contains("javascript") || value.contains("console") { return .javascriptErrors }
        if value.contains("canvas") || value.contains("blank") || value.contains("pixel") { return .canvas }
        if value.contains("heartbeat") { return .heartbeat }
        if value.contains("input") { return .input }
        if value.contains("restart") { return .restart }
        return .gameSpecific
    }

    private func checkSummary(for label: String) -> String {
        if let separator = label.firstIndex(of: ":") { return String(label[..<separator]) }
        return label
    }

    private func milliseconds(since start: Date) -> Int { max(0, Int(Date().timeIntervalSince(start) * 1000)) }

    private func safeFailureMessage(for error: Error) -> String {
        switch error {
        case ProviderError.missingKey: return "Add a provider key, then try again."
        case ProviderError.empty: return "The provider returned no usable candidate."
        case ProviderError.invalidProject: return "The current project could not be sent."
        case OrchestratorError.missingProject: return "Generate a game before applying an edit."
        case OrchestratorError.unrecoverableTransfer: return "The background request could not be recovered."
        case is CancellationError: return "Generation stopped."
        default: return "The provider or runtime could not complete the run."
        }
    }
}

nonisolated enum OrchestratorError: Error { case missingProject, unrecoverableTransfer, transferIdentityMismatch }
