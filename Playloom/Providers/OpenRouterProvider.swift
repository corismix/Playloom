import Foundation

nonisolated final class OpenRouterProvider: ModelProvider, Sendable {
    let displayName = "OpenRouter"
    private let keyStore: APIKeyStoring
    private let session: URLSession
    private let model: String

    init(keyStore: APIKeyStoring, session: URLSession = .shared, model: String = "openai/gpt-5-mini") { self.keyStore = keyStore; self.session = session; self.model = model }
    func generateProject(prompt: String) async throws -> GameProject { try await request(system: Self.generationPrompt, user: prompt) }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject {
        let data = try JSONEncoder().encode(project)
        guard let json = String(data: data, encoding: .utf8) else { throw ProviderError.invalidProject }
        return try await request(system: Self.generationPrompt + " Return the complete updated project.", user: "Current project:\n\(json)\n\nEdit:\n\(instruction)")
    }

    private func request(system: String, user: String) async throws -> GameProject {
        guard let key = try keyStore.read() else { throw ProviderError.missingKey }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/corismix/Playloom", forHTTPHeaderField: "HTTP-Referer"); request.setValue("Playloom", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: [.init(role: "system", content: system), .init(role: "user", content: user)], responseFormat: .init(type: "json_object")))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ProviderError.http((response as? HTTPURLResponse)?.statusCode ?? -1) }
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = envelope.choices.first?.message.content, let projectData = content.data(using: .utf8) else { throw ProviderError.empty }
        return try JSONDecoder().decode(GameProject.self, from: projectData).validated()
    }

    private static let generationPrompt = """
    Return only JSON matching {"title":String,"files":{"index.html":String,"game.js":String,"style.css":String}}. Build a touch-friendly Phaser 3 game. index.html loads vendor/phaser.min.js then game.js, has a local-only CSP, and a #game container. game.js exposes window.playloomProbeInput(), window.playloomRestart(), and window.playloomPixelSampleText(); sends ready, heartbeat, input, restarted, fatal and console events through window.webkit.messageHandlers.playloom.postMessage. No remote URLs, modules, eval, storage, fetch, sockets, navigation, or external assets. Use procedural graphics.
    """
}
private nonisolated struct ChatRequest: Encodable { let model: String; let messages: [Message]; let responseFormat: ResponseFormat; struct Message: Encodable { let role: String; let content: String }; struct ResponseFormat: Encodable { let type: String }; enum CodingKeys: String, CodingKey { case model, messages; case responseFormat = "response_format" } }
private nonisolated struct ChatResponse: Decodable { let choices: [Choice]; struct Choice: Decodable { let message: Message }; struct Message: Decodable { let content: String } }
nonisolated enum ProviderError: Error { case missingKey, http(Int), empty, invalidProject }
