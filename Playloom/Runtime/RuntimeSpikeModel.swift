import Observation

@MainActor
@Observable
final class RuntimeSpikeModel {
    let session = GameRuntimeSession()
    private(set) var state: RuntimeCheckState = .idle

    func start() { _ = session.makeWebView() }

    func runChecks() async {
        state = .running
        let report = await UniversalRuntimeChecker().run(session: session)
        state = report.isPassing ? .passed(report) : .failed(report)
    }

    func restart() { Task { try? await session.restart() } }
}
