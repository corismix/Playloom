import Foundation

nonisolated protocol ModelProvider: Sendable {
    var displayName: String { get }
    var supportsBackgroundContinuation: Bool { get }
    func generateProject(prompt: String) async throws -> GameProject
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject
    func generateProjectOutput(request: GenerationRequest) async throws -> GenerationProviderOutput
    func editProjectOutput(_ project: GameProject, request: GenerationRequest) async throws -> GenerationProviderOutput
    func acknowledge(_ output: GenerationProviderOutput) async throws
}

/// The provider-owned result of a request, including any durable transport
/// records that must remain available until the run has accepted the result.
nonisolated struct GenerationProviderOutput: Sendable, Equatable {
    let project: GameProject
    let backgroundTransfers: [BackgroundTransferMetadata]

    init(project: GameProject, backgroundTransfers: [BackgroundTransferMetadata] = []) {
        self.project = project
        self.backgroundTransfers = backgroundTransfers
    }
}

/// A provider with a durable transport that can be reconstructed after a
/// process relaunch. The orchestrator owns the recovery checkpoint and calls
/// `acknowledge` only after it has durably staged and journaled the candidate.
nonisolated protocol BackgroundRecoveringProvider: ModelProvider {
    var supportsBackgroundRecovery: Bool { get }
    func recoverBackgroundTransfers(for runID: RunID) async throws -> [BackgroundHTTPClient.TransferMetadata]
    func recoverProjectOutput(from transfer: BackgroundHTTPClient.TransferMetadata) async throws -> GenerationProviderOutput
    func cancelBackgroundTransfers(for runID: RunID) async throws
    func cleanupTerminalTransfers(retaining runIDs: Set<RunID>) throws
}

nonisolated struct GenerationRequest: Codable, Equatable, Sendable {
    let operation: GenerationOperationKind
    let projectID: ProjectID
    let runID: RunID
    let candidateID: CandidateID?
    let operationID: OperationID
    let baseRevisionID: BaseRevisionID
    let prompt: String
    let instruction: String?

    init(operation: GenerationOperationKind, projectID: ProjectID, runID: RunID,
         candidateID: CandidateID? = nil, operationID: OperationID = OperationID(), baseRevisionID: BaseRevisionID,
         prompt: String, instruction: String? = nil) {
        self.operation = operation; self.projectID = projectID; self.runID = runID
        self.candidateID = candidateID; self.operationID = operationID; self.baseRevisionID = baseRevisionID
        self.prompt = prompt; self.instruction = instruction
    }
}

extension ModelProvider {
    var supportsBackgroundContinuation: Bool { false }

    func generateProject(request: GenerationRequest) async throws -> GameProject {
        try await generateProject(prompt: request.prompt)
    }

    func editProject(_ project: GameProject, request: GenerationRequest) async throws -> GameProject {
        try await editProject(project, instruction: request.instruction ?? request.prompt)
    }

    func generateProjectOutput(request: GenerationRequest) async throws -> GenerationProviderOutput {
        GenerationProviderOutput(project: try await generateProject(request: request))
    }

    func editProjectOutput(_ project: GameProject, request: GenerationRequest) async throws -> GenerationProviderOutput {
        GenerationProviderOutput(project: try await editProject(project, request: request))
    }

    func acknowledge(_ output: GenerationProviderOutput) async throws {}
}
