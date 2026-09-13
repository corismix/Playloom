import Observation

@MainActor
@Observable
final class RuntimeSpikeModel {
    let session = GameRuntimeSession()
    private(set) var state: RuntimeCheckState = .idle

    func start() { _ = session.makeWebView() }

    func runChecks() async {
        state = .running
        do {
            let report = try await UniversalRuntimeChecker().run(session: session)
            state = report.isPassing ? .passed(report) : .failed(report)
        } catch is CancellationError {
            state = .failed(RuntimeReport(passed: [], failures: ["Runtime checks stopped."], console: []))
        } catch {
            state = .failed(RuntimeReport(passed: [], failures: ["Runtime checks could not complete."], console: []))
        }
    }

    func restart() { Task { try? await session.restart() } }
}
