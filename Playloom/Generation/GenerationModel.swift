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
    private var isAppActive = true
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
        isAppActive = false
        status = "Generating in background"
        detail = "You can lock your phone. Playloom will check the game when you return."
    }

    func didBecomeActive() {
        isAppActive = true
        guard isWorking, wasBackgroundedDuringGeneration else { return }
        status = "Resuming generation"
        detail = "If the provider finished, validation will start now."
    }

    private func perform(action: String, _ operation: () async throws -> GameProject) async {
        isWorking = true; wasBackgroundedDuringGeneration = false
        status = action
        detail = "Contacting \(provider.displayName). You may lock your phone; return later to validate the result."
        defer { isWorking = false; candidateSession = nil; UIApplication.shared.isIdleTimerDisabled = false }
        do {
            let candidate = try await operation()
            try persistPending(candidate)
            while !isAppActive { try await ContinuousClock().sleep(for: .milliseconds(250)) }
            UIApplication.shared.isIdleTimerDisabled = true
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
            clearPending()
            status = "Playable"
            detail = "Passed: " + report.passed.joined(separator: ", ")
        } catch {
            status = wasBackgroundedDuringGeneration ? "Request stopped while app was inactive" : "Generation failed"
            detail = "\(error.localizedDescription). The last playable game was preserved; retry when ready and keep Playloom open."
        }
    }

    private var pendingURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appending(path: "pending-generated-project.json")
    }
    private func persistPending(_ candidate: GameProject) throws { try JSONEncoder().encode(candidate).write(to: pendingURL, options: .atomic) }
    private func clearPending() { try? FileManager.default.removeItem(at: pendingURL) }

}
