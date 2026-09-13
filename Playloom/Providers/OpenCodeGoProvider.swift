import Foundation

nonisolated final class OpenCodeGoProvider: ModelProvider, Sendable {
    let displayName = "OpenCode Go"
    var supportsBackgroundContinuation: Bool { backgroundClient != nil }
    private let keyStore: APIKeyStoring
    private let session: URLSession
    private let model: String
    private let conversationID: String
    private let backgroundClient: BackgroundHTTPClient?

    init(keyStore: APIKeyStoring, session: URLSession? = nil, model: String = "deepseek-v4.1-flash", conversationID: String = UUID().uuidString) {
        self.keyStore = keyStore; self.model = model; self.conversationID = conversationID
        self.backgroundClient = session == nil ? .shared : nil
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 300
            configuration.timeoutIntervalForResource = 360
            self.session = URLSession(configuration: configuration)
        }
    }

    func generateProject(prompt: String) async throws -> GameProject { try await request(user: prompt, effort: .max, context: Self.context(operation: .generate, prompt: prompt)) }
    func generateProject(request contextRequest: GenerationRequest) async throws -> GameProject {
        try await self.request(user: contextRequest.prompt, effort: .max, context: contextRequest)
    }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject {
        let data = try JSONEncoder().encode(project)
        guard let json = String(data: data, encoding: .utf8) else { throw ProviderError.invalidProject }
        return try await request(user: "Current project:\n\(json)\n\nEdit:\n\(instruction)\nReturn the complete updated project.", effort: .high, context: Self.context(operation: .edit, prompt: "", instruction: instruction))
    }
    func editProject(_ project: GameProject, request: GenerationRequest) async throws -> GameProject {
        let data = try JSONEncoder().encode(project)
        guard let json = String(data: data, encoding: .utf8) else { throw ProviderError.invalidProject }
        return try await self.request(user: "Current project:\n\(json)\n\nEdit:\n\(request.instruction ?? request.prompt)\nReturn the complete updated project.", effort: .high, context: request)
    }

    func backgroundTransferMetadata(for runID: RunID) -> [BackgroundHTTPClient.TransferMetadata] {
        backgroundClient?.metadata(for: runID) ?? []
    }

    func recoverBackgroundTransfers(for runID: RunID) async throws -> [BackgroundHTTPClient.TransferMetadata] {
        guard let backgroundClient else { return [] }
        let transfers = try await backgroundClient.recover(for: runID)
        return transfers.filter { $0.runID == runID }
    }

    func recoverProject(from transfer: BackgroundHTTPClient.TransferMetadata) async throws -> GameProject {
        guard let backgroundClient else { throw OpenCodeGoError.invalidResponse }
        let result = try await backgroundClient.waitForTransfer(taskIdentifier: transfer.taskIdentifier)
        let project = try decodeProjectResponse(data: result.data, response: result.response)
        try backgroundClient.acknowledgeTransfer(taskIdentifier: result.taskIdentifier)
        return project
    }

    private func request(user: String, effort: ReasoningEffort, context: GenerationRequest) async throws -> GameProject {
        guard let key = try keyStore.read() else { throw ProviderError.missingKey }
        let first = try await completion(key: key, messages: [.init(role: "system", content: Self.prompt), .init(role: "user", content: user)], effort: effort, context: context)
        let project: GameProject
        do {
            project = try Self.decodeProject(from: first.content)
        } catch {
            let shape = Self.responseShape(first.content)
            let repair = """
            Your prior answer could not be decoded as the required project JSON (\(shape)). Return the same project again as one valid JSON object only. No markdown, analysis, preface, suffix, or unescaped newlines inside JSON strings. Required keys: title and files; files must contain index.html, game.js, and style.css.
            """
            let second = try await completion(key: key, messages: [.init(role: "system", content: Self.prompt), .init(role: "user", content: user), .init(role: "assistant", content: first.content), .init(role: "user", content: repair)], effort: .low, context: context)
            let repaired: GameProject
            do { repaired = try Self.decodeProject(from: second.content) }
            catch { throw OpenCodeGoError.unparseable(first: shape, repair: Self.responseShape(second.content)) }
            try acknowledge(first)
            try acknowledge(second)
            print("PLAYLOOM_OPENCODE_REPAIR_USED=true")
            return repaired
        }
        try acknowledge(first)
        print("PLAYLOOM_OPENCODE_REPAIR_USED=false")
        return project
    }

    private struct ProviderResponse: Sendable {
        let content: String
        let taskIdentifier: Int?
    }

    private func acknowledge(_ response: ProviderResponse) throws {
        guard let taskIdentifier = response.taskIdentifier, let backgroundClient else { return }
        try backgroundClient.acknowledgeTransfer(taskIdentifier: taskIdentifier)
    }

    private func completion(key: String, messages: [Request.Message], effort: ReasoningEffort, context: GenerationRequest) async throws -> ProviderResponse {
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("playloom-ios/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(conversationID, forHTTPHeaderField: "x-opencode-session")
        let body = try JSONEncoder().encode(Request(model: model, messages: messages, thinking: .init(type: "enabled"), reasoningEffort: effort))
        let data: Data
        let response: URLResponse
        let taskIdentifier: Int?
        if let backgroundClient {
            let transfer = try await backgroundClient.upload(for: request, body: body, context: context)
            data = transfer.data
            response = transfer.response
            taskIdentifier = transfer.taskIdentifier
        } else {
            request.httpBody = body
            (data, response) = try await session.data(for: request)
            taskIdentifier = nil
        }
        guard let http = response as? HTTPURLResponse else { throw OpenCodeGoError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OpenCodeGoError.http(status: http.statusCode, providerMessage: Self.sanitizedError(data)) }
        let envelope = try JSONDecoder().decode(Response.self, from: data)
        guard let content = envelope.choices.first?.message.content, !content.isEmpty else { throw ProviderError.empty }
        return ProviderResponse(content: content, taskIdentifier: taskIdentifier)
    }

    private func decodeProjectResponse(data: Data, response: URLResponse) throws -> GameProject {
        guard let http = response as? HTTPURLResponse else { throw OpenCodeGoError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OpenCodeGoError.http(status: http.statusCode, providerMessage: Self.sanitizedError(data)) }
        let envelope = try JSONDecoder().decode(Response.self, from: data)
        guard let content = envelope.choices.first?.message.content, !content.isEmpty else { throw ProviderError.empty }
        return try Self.decodeProject(from: content)
    }

    private static func context(operation: GenerationOperationKind, prompt: String, instruction: String? = nil) -> GenerationRequest {
        GenerationRequest(operation: operation, projectID: ProjectID(), runID: RunID(), baseRevisionID: BaseRevisionID(), prompt: prompt, instruction: instruction)
    }

    static func decodeProject(from text: String) throws -> GameProject {
        let object = try extractJSONObject(text)
        guard let data = object.data(using: .utf8) else { throw ProviderError.empty }
        return try JSONDecoder().decode(GameProject.self, from: data).validated()
    }

    static func extractJSONObject(_ text: String) throws -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fencePattern = #"(?s)```(?:json)?\s*(\{.*\})\s*```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) { return String(cleaned[range]) }
        guard let start = cleaned.firstIndex(of: "{") else { throw OpenCodeGoError.noJSONObject(Self.responseShape(cleaned)) }
        var depth = 0; var inString = false; var escaped = false
        for index in cleaned.indices[start...] {
            let character = cleaned[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" { inString = true }
            else if character == "{" { depth += 1 }
            else if character == "}" { depth -= 1; if depth == 0 { return String(cleaned[start...index]) } }
        }
        throw OpenCodeGoError.noJSONObject(Self.responseShape(cleaned))
    }

    static func responseShape(_ text: String) -> String {
        let prefix = text.prefix(160).map { $0.isNewline ? "↵" : $0 }.reduce("", { $0 + String($1) })
        return "chars=\(text.count), first=\(text.first.map(String.init) ?? "none"), last=\(text.last.map(String.init) ?? "none"), fences=\(text.components(separatedBy: "```").count - 1), prefix=\(prefix)"
    }

    static func sanitizedError(_ data: Data) -> String {
        let raw = (String(data: data, encoding: .utf8) ?? "unreadable response").prefix(1000)
        return raw.replacingOccurrences(of: "Bearer ", with: "Bearer [redacted]", options: .caseInsensitive)
    }

    private static let prompt = """
    Return only JSON matching {"title":String,"files":{"index.html":String,"game.js":String,"style.css":String}}. Build a polished one-screen touch-first Phaser 3 game with procedural graphics. The complete game must be playable on an iPhone with visible on-screen controls or canvas pointer gestures; never make keyboard input the only control path. index.html must load vendor/phaser.min.js then game.js, set a local-only CSP, and contain #game. game.js must expose playloomProbeInput, playloomRestart, and playloomPixelSampleText. Route real Phaser pointer/touch input and playloomProbeInput through the same gameplay handler, and have that handler send the input bridge event; do not emit input merely because the probe function was called. Send ready, heartbeat, input, restarted, fatal and console messages through window.webkit.messageHandlers.playloom.postMessage. No remote URLs, modules, eval, storage, fetch, sockets, navigation, or external assets. Keep all source under 512KB. JSON string values must escape every newline as \\n.
    """
}

nonisolated enum ReasoningEffort: String, Encodable { case low, high, max }
private nonisolated struct Request: Encodable {
    let model: String
    let messages: [Message]
    let thinking: Thinking
    let reasoningEffort: ReasoningEffort
    struct Message: Encodable { let role: String; let content: String }
    struct Thinking: Encodable { let type: String }
    enum CodingKeys: String, CodingKey {
        case model, messages, thinking
        case reasoningEffort = "reasoning_effort"
    }
}
private nonisolated struct Response: Decodable { let choices: [Choice]; struct Choice: Decodable { let message: Message }; struct Message: Decodable { let content: String } }
nonisolated enum OpenCodeGoError: Error, LocalizedError, CustomStringConvertible {
    case invalidResponse, noJSONObject(String), unparseable(first: String, repair: String), http(status: Int, providerMessage: String)
    var errorDescription: String? { description }
    var description: String { switch self {
    case .invalidResponse: "OpenCode Go returned a response Playloom could not read. Try again."
    case .noJSONObject(let shape): "OpenCode Go did not return project JSON (\(shape))."
    case let .unparseable(first, repair): "OpenCode Go returned malformed project JSON twice. First response: [\(first)]. Repair response: [\(repair)]."
    case let .http(status, message): "OpenCode Go request failed with HTTP \(status): \(message)"
    } }
}
