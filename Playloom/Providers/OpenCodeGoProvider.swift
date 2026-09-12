import Foundation

nonisolated final class OpenCodeGoProvider: ModelProvider, Sendable {
    private let keyStore: APIKeyStoring; private let session: URLSession; private let model: String
    init(keyStore: APIKeyStoring, session: URLSession = .shared, model: String = "deepseek-v4.1-flash") { self.keyStore=keyStore; self.session=session; self.model=model }
    func generateProject(prompt: String) async throws -> GameProject { try await request(user: prompt) }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject {
        let data=try JSONEncoder().encode(project); guard let json=String(data:data,encoding:.utf8) else { throw ProviderError.invalidProject }
        return try await request(user:"Current project:\n\(json)\n\nEdit:\n\(instruction)\nReturn the complete updated project.")
    }
    private func request(user: String) async throws -> GameProject {
        guard let key=try keyStore.read() else { throw ProviderError.missingKey }
        var req=URLRequest(url:URL(string:"https://opencode.ai/zen/go/v1/chat/completions")!); req.httpMethod="POST"
        req.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONEncoder().encode(Request(model:model,messages:[.init(role:"system",content:Self.prompt),.init(role:"user",content:user)],maxTokens:12000))
        let (data,response)=try await session.data(for:req)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else { throw ProviderError.http((response as? HTTPURLResponse)?.statusCode ?? -1) }
        let envelope=try JSONDecoder().decode(Response.self,from:data)
        guard let content=envelope.choices.first?.message.content,let projectData=Self.extractJSONObject(content).data(using:.utf8) else { throw ProviderError.empty }
        return try JSONDecoder().decode(GameProject.self,from:projectData).validated()
    }
    static func extractJSONObject(_ text:String)->String { guard let a=text.firstIndex(of:"{"),let b=text.lastIndex(of:"}"),a<=b else{return text}; return String(text[a...b]) }
    private static let prompt="""
    Return only JSON matching {"title":String,"files":{"index.html":String,"game.js":String,"style.css":String}}. Build a polished one-screen touch-friendly Phaser 3 game with procedural graphics. index.html must load vendor/phaser.min.js then game.js, set a local-only CSP, and contain #game. game.js must expose playloomProbeInput, playloomRestart, and playloomPixelSampleText; send ready, heartbeat, input, restarted, fatal and console messages through window.webkit.messageHandlers.playloom.postMessage. No remote URLs, modules, eval, storage, fetch, sockets, navigation, or external assets. Keep all source under 512KB.
    """
}
private nonisolated struct Request:Encodable { let model:String;let messages:[Message];let maxTokens:Int;struct Message:Encodable{let role:String;let content:String};enum CodingKeys:String,CodingKey{case model,messages;case maxTokens="max_tokens"} }
private nonisolated struct Response:Decodable { let choices:[Choice];struct Choice:Decodable{let message:Message};struct Message:Decodable{let content:String} }
