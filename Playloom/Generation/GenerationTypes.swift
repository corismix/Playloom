import Foundation

// These identifiers are intentionally UUID-backed but encode as stable strings.
nonisolated struct ProjectID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    init?(rawValue: String) { guard let value = UUID(uuidString: rawValue) else { return nil }; self.rawValue = value }
    var description: String { rawValue.uuidString }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); guard let id = UUID(uuidString: try c.decode(String.self)) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid project ID") }; self.init(id) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(description) }
}

nonisolated struct RunID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    init?(rawValue: String) { guard let value = UUID(uuidString: rawValue) else { return nil }; self.rawValue = value }
    var description: String { rawValue.uuidString }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); guard let id = UUID(uuidString: try c.decode(String.self)) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid run ID") }; self.init(id) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(description) }
}

nonisolated struct CandidateID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    init?(rawValue: String) { guard let value = UUID(uuidString: rawValue) else { return nil }; self.rawValue = value }
    var description: String { rawValue.uuidString }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); guard let id = UUID(uuidString: try c.decode(String.self)) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid candidate ID") }; self.init(id) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(description) }
}

nonisolated struct OperationID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    init?(rawValue: String) { guard let value = UUID(uuidString: rawValue) else { return nil }; self.rawValue = value }
    var description: String { rawValue.uuidString }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); guard let id = UUID(uuidString: try c.decode(String.self)) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid operation ID") }; self.init(id) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(description) }
}

nonisolated struct BaseRevisionID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    init?(rawValue: String) { guard let value = UUID(uuidString: rawValue) else { return nil }; self.rawValue = value }
    var description: String { rawValue.uuidString }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); guard let id = UUID(uuidString: try c.decode(String.self)) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid base revision ID") }; self.init(id) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(description) }
}

nonisolated enum GenerationOperationKind: String, Codable, Equatable, Sendable { case generate, edit }
nonisolated enum GenerationStage: String, Codable, Equatable, Sendable { case planning, generating, receiving, staging, validating, launching, checking, resampling, promoting }
nonisolated enum GenerationCheckKind: String, Codable, Equatable, Sendable { case bridge, load, javascriptErrors, canvas, heartbeat, input, restart, gameSpecific }
nonisolated enum GenerationCheckStatus: String, Codable, Equatable, Sendable { case passed, failed, skipped, unavailable }
nonisolated enum GenerationEventKind: String, Codable, Equatable, Sendable { case runCreated, stageStarted, stageFinished, providerOutputReceived, candidateStaged, checkFinished, retryStarted, lifecycleChanged, keepOpenWarning, cancellationRequested, staleCompletion, cancelled, failed, completed }
nonisolated enum RunLifecycle: String, Codable, Equatable, Sendable { case foreground, suspended, relaunchedInterrupted, forceQuitUnknown, cancelled, failed, completed }
nonisolated enum RunRecoveryReason: String, Codable, Equatable, Sendable { case osRelaunchInterrupted, forceQuitUnknown }
nonisolated enum GenerationOutcomeStatus: String, Codable, Equatable, Sendable { case completed, failed, cancelled }
nonisolated enum BackgroundTransferState: String, Codable, Equatable, Sendable { case running, completed, failed, cancelled, interrupted }

nonisolated enum BackgroundTransferHeaderPolicy {
    static let persistedNames: Set<String> = ["content-type", "content-length", "retry-after"]

    static func sanitize(_ headers: [AnyHashable: Any]) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            let name = String(describing: item.key).lowercased()
            guard persistedNames.contains(name) else { return }
            result[name] = String(describing: item.value)
        }
    }

    static func sanitize(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            let name = item.key.lowercased()
            guard persistedNames.contains(name) else { return }
            result[name] = item.value
        }
    }
}

nonisolated struct GenerationPlan: Codable, Equatable, Sendable {
    var coreLoop: String
    var actions: [String]
    var controls: [String]
    var entities: [String]
    var winConditions: [String]
    var loseConditions: [String]
    var doneWhenChecks: [String]
}

nonisolated struct GenerationOperation: Codable, Equatable, Sendable {
    let id: OperationID
    let kind: GenerationOperationKind
    let stage: GenerationStage
    let candidateID: CandidateID?
    let baseRevisionID: BaseRevisionID
    let retryRound: Int?
}

nonisolated struct GenerationCheckResult: Codable, Equatable, Sendable {
    let kind: GenerationCheckKind
    let status: GenerationCheckStatus
    let summary: String
    let detail: String?
    let durationMilliseconds: Int?
}

nonisolated struct FileDiffSummary: Codable, Equatable, Sendable {
    let added: [String]
    let changed: [String]
    let removed: [String]
    let totalBytes: Int?
}

nonisolated struct UsageSummary: Codable, Equatable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let costMicros: Int?
}

nonisolated struct BackgroundTransferMetadata: Codable, Equatable, Sendable {
    let taskIdentifier: Int
    let projectID: ProjectID?
    let runID: RunID?
    let operationID: OperationID?
    let candidateID: CandidateID?
    let baseRevisionID: BaseRevisionID?
    let requestBodyURL: String?
    let responseURL: String?
    let providerRequestID: String?
    let state: BackgroundTransferState
    let updatedAt: Date
    let statusCode: Int?
    let responseHeaders: [String: String]

    init(
        taskIdentifier: Int,
        projectID: ProjectID? = nil,
        runID: RunID? = nil,
        operationID: OperationID? = nil,
        candidateID: CandidateID? = nil,
        baseRevisionID: BaseRevisionID? = nil,
        requestBodyURL: String? = nil,
        responseURL: String? = nil,
        providerRequestID: String? = nil,
        state: BackgroundTransferState = .running,
        updatedAt: Date = Date(),
        statusCode: Int? = nil,
        responseHeaders: [String: String] = [:]
    ) {
        self.taskIdentifier = taskIdentifier
        self.projectID = projectID
        self.runID = runID
        self.operationID = operationID
        self.candidateID = candidateID
        self.baseRevisionID = baseRevisionID
        self.requestBodyURL = requestBodyURL
        self.responseURL = responseURL
        self.providerRequestID = providerRequestID
        self.state = state
        self.updatedAt = updatedAt
        self.statusCode = statusCode
        self.responseHeaders = BackgroundTransferHeaderPolicy.sanitize(responseHeaders)
    }

    private enum CodingKeys: String, CodingKey {
        case taskIdentifier, projectID, runID, operationID, candidateID, baseRevisionID
        case requestBodyURL, responseURL, providerRequestID, state, updatedAt, statusCode, responseHeaders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            taskIdentifier: try container.decode(Int.self, forKey: .taskIdentifier),
            projectID: try container.decodeIfPresent(ProjectID.self, forKey: .projectID),
            runID: try container.decodeIfPresent(RunID.self, forKey: .runID),
            operationID: try container.decodeIfPresent(OperationID.self, forKey: .operationID),
            candidateID: try container.decodeIfPresent(CandidateID.self, forKey: .candidateID),
            baseRevisionID: try container.decodeIfPresent(BaseRevisionID.self, forKey: .baseRevisionID),
            requestBodyURL: try container.decodeIfPresent(String.self, forKey: .requestBodyURL),
            responseURL: try container.decodeIfPresent(String.self, forKey: .responseURL),
            providerRequestID: try container.decodeIfPresent(String.self, forKey: .providerRequestID),
            state: try container.decode(BackgroundTransferState.self, forKey: .state),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            statusCode: try container.decodeIfPresent(Int.self, forKey: .statusCode),
            responseHeaders: try container.decodeIfPresent([String: String].self, forKey: .responseHeaders) ?? [:]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskIdentifier, forKey: .taskIdentifier)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(runID, forKey: .runID)
        try container.encodeIfPresent(operationID, forKey: .operationID)
        try container.encodeIfPresent(candidateID, forKey: .candidateID)
        try container.encodeIfPresent(baseRevisionID, forKey: .baseRevisionID)
        try container.encodeIfPresent(requestBodyURL, forKey: .requestBodyURL)
        try container.encodeIfPresent(responseURL, forKey: .responseURL)
        try container.encodeIfPresent(providerRequestID, forKey: .providerRequestID)
        try container.encode(state, forKey: .state)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(statusCode, forKey: .statusCode)
        try container.encode(BackgroundTransferHeaderPolicy.sanitize(responseHeaders), forKey: .responseHeaders)
    }
}

nonisolated struct GenerationEvent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let projectID: ProjectID
    let runID: RunID
    let candidateID: CandidateID?
    let operationID: OperationID?
    let baseRevisionID: BaseRevisionID
    let kind: GenerationEventKind
    let lifecycle: RunLifecycle?
    let stage: GenerationStage?
    let summary: String
    let detail: String?
    let check: GenerationCheckResult?
    let fileDiff: FileDiffSummary?
    let retryRound: Int?
    let durationMilliseconds: Int?
    let usage: UsageSummary?
    let backgroundTransfer: BackgroundTransferMetadata?
}

nonisolated struct GenerationOutcome: Codable, Equatable, Sendable {
    let status: GenerationOutcomeStatus
    let timestamp: Date
    let summary: String
    let detail: String?
    let candidateID: CandidateID?
    let durationMilliseconds: Int?
    let usage: UsageSummary?
}

nonisolated struct PassingProjectMetadata: Codable, Equatable, Sendable {
    let baseRevisionID: BaseRevisionID
    let candidateID: CandidateID?
    let title: String
    let filePaths: [String]
    let updatedAt: Date

    init(
        baseRevisionID: BaseRevisionID,
        candidateID: CandidateID? = nil,
        title: String,
        filePaths: [String],
        updatedAt: Date
    ) {
        self.baseRevisionID = baseRevisionID
        self.candidateID = candidateID
        self.title = title
        self.filePaths = filePaths
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case baseRevisionID, candidateID, title, filePaths, updatedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            baseRevisionID: try container.decode(BaseRevisionID.self, forKey: .baseRevisionID),
            candidateID: try container.decodeIfPresent(CandidateID.self, forKey: .candidateID),
            title: try container.decode(String.self, forKey: .title),
            filePaths: try container.decode([String].self, forKey: .filePaths),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

nonisolated struct GenerationRun: Codable, Equatable, Sendable {
    let projectID: ProjectID
    let id: RunID
    let createdAt: Date
    var lifecycle: RunLifecycle
    var baseRevisionID: BaseRevisionID
    var plan: GenerationPlan?
    var operations: [GenerationOperation]
    var events: [GenerationEvent]
    var outcome: GenerationOutcome?
    var currentStage: GenerationStage? = nil
    var backgroundTransfers: [BackgroundTransferMetadata] = []
}
