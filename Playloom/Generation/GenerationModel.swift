import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GenerationModel {
    var prompt = "Make a one-screen game where I dodge falling stars"
    var edit = "Make the player faster"
    var apiKey = ""
    private(set) var status = "Add an OpenCode Go key to begin"
    private(set) var detail = ""
    private(set) var isWorking = false
    private(set) var wasBackgroundedDuringGeneration = false
    private(set) var session: GameRuntimeSession?
    private(set) var candidateSession: GameRuntimeSession?
    private(set) var project: GameProject?
    var apiKeyLabel: String { "\(provider.displayName) API key" }

    private let keyStore: APIKeyStore
    private let provider: ModelProvider
    private let workspace: ProjectWorkspace

    init(keyStore: APIKeyStore = APIKeyStore(account: "opencode-go"), provider: ModelProvider? = nil) {
        self.keyStore = keyStore
        self.provider = provider ?? OpenCodeGoProvider(keyStore: keyStore)
        self.workspace = try! ProjectWorkspace()
        if (try? keyStore.read()) != nil { status = "Ready" }
    }

    func saveKey() {
        do { try keyStore.save(apiKey); apiKey = ""; status = "OpenCode Go key saved in Keychain"; detail = "Ready to generate." }
        catch { status = "Could not save key"; detail = error.localizedDescription }
    }

    func generate() async { await perform(action: "Generating project") { try await provider.generateProject(prompt: prompt) } }
    func applyEdit() async {
        guard let project else { status = "Generate a game first"; return }
        await perform(action: "Generating edit") { try await provider.editProject(project, instruction: edit) }
    }

    func didEnterBackground() {
        guard isWorking else { return }
        wasBackgroundedDuringGeneration = true
        status = "Generation interrupted by lock/background"
        detail = "Return to Playloom and keep it open. The last playable game is safe."
    }

    func didBecomeActive() {
        guard isWorking, wasBackgroundedDuringGeneration else { return }
        status = "Checking request after interruption"
        detail = "Keep Playloom open. If iOS stopped the request, you can retry without losing the last playable game."
    }

    private func perform(action: String, _ operation: () async throws -> GameProject) async {
        isWorking = true; wasBackgroundedDuringGeneration = false
        status = action
        detail = "Contacting \(provider.displayName). Keep Playloom open and unlocked; this can take several minutes."
        UIApplication.shared.isIdleTimerDisabled = true
        defer { isWorking = false; candidateSession = nil; UIApplication.shared.isIdleTimerDisabled = false }
        do {
            let candidate = try await operation()
            status = "Staging generated files"; detail = "Checking project structure and copying the local Phaser runtime."
            let directory = try workspace.stage(candidate)
            status = "Starting game runtime"; detail = "Loading the candidate in a sandboxed WebKit view."
            let checkingSession = GameRuntimeSession(projectDirectory: directory)
            candidateSession = checkingSession
            _ = checkingSession.makeWebView()
            status = "Running 6 safety checks"; detail = "Load, JavaScript, canvas, heartbeat, input, and restart."
            // Yield so SwiftUI presents the candidate at full opacity before WebKit checks.
            await Task.yield()
            let report = await UniversalRuntimeChecker().run(session: checkingSession)
            guard report.isPassing else {
                status = "Candidate rejected"
                detail = report.failures.joined(separator: " | ")
                return
            }
            project = candidate; session = checkingSession
            status = "Playable"
            detail = "Passed: " + report.passed.joined(separator: ", ")
        } catch {
            status = wasBackgroundedDuringGeneration ? "Request stopped while app was inactive" : "Generation failed"
            detail = "\(error.localizedDescription). The last playable game was preserved; retry when ready and keep Playloom open."
        }
    }
}
