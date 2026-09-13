import Foundation
import Observation

@MainActor
@Observable
final class GenerationModel {
    var prompt = "Make a one-screen game where I dodge falling stars"
    var edit = "Make the player faster"
    var apiKey = ""

    private(set) var isWorking = false
    private(set) var activityEvents: [GenerationEvent] = []
    private(set) var session: GameRuntimeSession?
    private(set) var candidateSession: GameRuntimeSession?
    private(set) var project: GameProject?

    var events: [GenerationEvent] { activityEvents }
    var apiKeyLabel: String { "\(provider.displayName) API key" }

    /// Compatibility accessors for the existing shell and tests. Generation UI
    /// itself renders the typed event stream through ActivityCard.
    var status: String {
        guard let latest = activityEvents.last else { return setupStatus }
        switch latest.kind {
        case .completed: return "Playable"
        case .cancelled: return "Generation stopped"
        case .failed, .staleCompletion: return latest.summary
        default: return latest.summary
        }
    }

    var detail: String {
        if let latest = activityEvents.last { return latest.detail ?? "" }
        return setupDetail
    }

    var wasBackgroundedDuringGeneration: Bool {
        guard let runID = activityEvents.last?.runID else { return false }
        return activityEvents.contains { $0.runID == runID && $0.lifecycle == .suspended }
    }

    private(set) var setupStatus = "Add an OpenCode Go key to begin"
    private(set) var setupDetail = ""

    private let keyStore: APIKeyStore
    private let provider: ModelProvider
    private let projectID: ProjectID
    private let orchestrator: GenerationOrchestrator
    private var streamTask: Task<Void, Never>?

    init(
        keyStore: APIKeyStore = APIKeyStore(account: "opencode-go"),
        provider: ModelProvider? = nil,
        projectID: ProjectID? = nil,
        journal: RunJournal? = nil,
        workspace: ProjectWorkspace? = nil,
        runtimeCheck: @escaping @MainActor (GameRuntimeSession) async -> RuntimeReport = { session in
            await UniversalRuntimeChecker().run(session: session)
        }
    ) {
        self.keyStore = keyStore
        self.provider = provider ?? OpenCodeGoProvider(keyStore: keyStore)

        let resolved = projectID ?? Self.loadOrCreateProjectID()
        self.projectID = resolved
        let resolvedJournal = journal ?? (try! RunJournal(fileURL: Self.defaultJournalURL(), projectID: resolved))
        let resolvedWorkspace = workspace ?? (try! ProjectWorkspace())
        self.orchestrator = GenerationOrchestrator(
            projectID: resolved,
            provider: self.provider,
            journal: resolvedJournal,
            workspace: resolvedWorkspace,
            runtimeCheck: runtimeCheck
        )
        if (try? keyStore.read()) != nil {
            setupStatus = "Ready"
        }

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = self.orchestrator.eventStream()
            for await event in stream {
                guard !self.activityEvents.contains(where: { $0.id == event.id }) else { continue }
                self.activityEvents.append(event)
                self.syncFromOrchestrator()
            }
        }
    }

    func saveKey() {
        do {
            try keyStore.save(apiKey)
            apiKey = ""
            setupStatus = "OpenCode Go key saved in Keychain"
            setupDetail = "Ready to generate."
        } catch {
            setupStatus = "Could not save key"
            setupDetail = "The key could not be saved."
        }
    }

    func generate() async {
        guard !isWorking else { return }
        isWorking = true
        let task = await orchestrator.startGenerate(prompt: prompt)
        _ = await task.value
        syncFromOrchestrator()
        isWorking = false
    }

    func applyEdit() async {
        guard let project else {
            setupStatus = "Generate a game first"
            setupDetail = "Create a playable project before applying an edit."
            return
        }
        guard !isWorking else { return }
        isWorking = true
        let task = await orchestrator.startEdit(project: project, instruction: edit)
        let result = await task.value
        syncFromOrchestrator()
        if result.succeeded { edit = "" }
        isWorking = false
    }

    func stop() { orchestrator.cancel() }

    func didEnterBackground() { orchestrator.didEnterBackground() }

    func didBecomeActive() { orchestrator.didBecomeActive() }

    func restoreOnLaunch(as reason: RunRecoveryReason = .forceQuitUnknown) async {
        await orchestrator.loadPersistedActivity()
        await orchestrator.recoverOnLaunch(as: reason)
        syncFromOrchestrator()
    }

    private func syncFromOrchestrator() {
        isWorking = orchestrator.isWorking
        session = orchestrator.session
        candidateSession = orchestrator.candidateSession
        if let accepted = orchestrator.project { project = accepted }
        let known = Set(activityEvents.map(\.id))
        activityEvents.append(contentsOf: orchestrator.events.filter { !known.contains($0.id) })
    }

    private static func defaultJournalURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Playloom", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appending(path: "run-journal.json")
    }

    private static func loadOrCreateProjectID() -> ProjectID {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Playloom", directoryHint: .isDirectory)
        let url = root.appending(path: "project-id.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url), let existing = try? JSONDecoder().decode(ProjectIdentity.self, from: data) {
            return existing.projectID
        }
        let identity = ProjectIdentity(projectID: ProjectID())
        if let data = try? JSONEncoder().encode(identity) { try? data.write(to: url, options: .atomic) }
        return identity.projectID
    }
}

private struct ProjectIdentity: Codable { let projectID: ProjectID }
