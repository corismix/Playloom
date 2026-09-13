import Foundation

nonisolated protocol ModelProvider: Sendable {
    var displayName: String { get }
    var supportsBackgroundContinuation: Bool { get }
    func generateProject(prompt: String) async throws -> GameProject
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject
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
}
