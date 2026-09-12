import Foundation
import Observation

@MainActor
@Observable
final class GenerationModel {
    var prompt = "Make a one-screen game where I dodge falling stars"
    var edit = "Make the player faster"
    var apiKey = ""
    private(set) var status = "Add an OpenRouter key to begin"
    private(set) var isWorking = false
    private(set) var session: GameRuntimeSession?
    private(set) var project: GameProject?

    private let keyStore: APIKeyStore
    private let provider: ModelProvider
    private let workspace: ProjectWorkspace

    init(keyStore: APIKeyStore = APIKeyStore(account: "openrouter"), provider: ModelProvider? = nil) {
        self.keyStore = keyStore
        self.provider = provider ?? OpenRouterProvider(keyStore: keyStore)
        self.workspace = try! ProjectWorkspace()
        if (try? keyStore.read()) != nil { status = "Ready" }
    }

    func saveKey() {
        do { try keyStore.save(apiKey); apiKey = ""; status = "OpenRouter key saved in Keychain" }
        catch { status = "Could not save key: \(error.localizedDescription)" }
    }

    func generate() async { await perform { try await provider.generateProject(prompt: prompt) } }
    func applyEdit() async {
        guard let project else { status = "Generate a game first"; return }
        await perform { try await provider.editProject(project, instruction: edit) }
    }

    private func perform(_ operation: () async throws -> GameProject) async {
        isWorking = true; status = "Generating"
        defer { isWorking = false }
        do {
            let candidate = try await operation()
            status = "Validating and loading"
            let directory = try workspace.stage(candidate)
            let candidateSession = GameRuntimeSession(projectDirectory: directory)
            _ = candidateSession.makeWebView()
            let report = await UniversalRuntimeChecker().run(session: candidateSession)
            guard report.isPassing else { status = "Rejected: " + report.failures.joined(separator: ", "); return }
            project = candidate; session = candidateSession; status = "Playable: \(report.passed.count) checks passed"
        } catch { status = "Failed: \(error.localizedDescription)" }
    }
}
