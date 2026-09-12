import Foundation

@MainActor
struct UniversalRuntimeChecker {
    func run(session: GameRuntimeSession) async -> RuntimeReport {
        var passed: [String] = []
        var failures: [String] = []
        session.beginValidationPresentation()
        defer { session.endValidationPresentation() }

        if await session.waitFor({ $0 == .bridgeReady }, timeout: .seconds(15)) { passed.append("WebKit bridge ready") }
        else { failures.append("WebKit startup failed: " + session.startupDiagnostic) }

        if await session.waitFor({ $0 == .ready }, timeout: .seconds(15)) { passed.append("loads") }
        else { failures.append("game ready timeout: " + session.startupDiagnostic) }

        let fatal = session.events.compactMap { event -> String? in
            if case .fatal(let message) = event { return message }
            if case .console(let level, let message) = event, level == "error" { return message }
            return nil
        }
        if fatal.isEmpty { passed.append("no JavaScript crash") }
        else { failures.append("JavaScript: " + fatal.joined(separator: "; ")) }

        do {
            let pixels = try await session.samplePixels()
            if pixels.isNonBlank { passed.append("canvas not blank") }
            else { failures.append("blank canvas") }
        } catch { failures.append("pixel sample failed: \(error.localizedDescription)") }

        let initialFrames = session.events.filter { if case .heartbeat = $0 { true } else { false } }.count
        try? await ContinuousClock().sleep(for: .milliseconds(200))
        let laterFrames = session.events.filter { if case .heartbeat = $0 { true } else { false } }.count
        if laterFrames > initialFrames { passed.append("heartbeat alive") }
        else { failures.append("heartbeat stalled") }

        do {
            try await session.probeInput()
            if await session.waitFor({ $0 == .inputReceived }, timeout: .seconds(1)) { passed.append("input works") }
            else { failures.append("input probe failed") }
        } catch { failures.append("input probe failed") }

        do {
            try await session.restart()
            if await session.waitFor({ $0 == .restarted }, timeout: .seconds(1)) { passed.append("restart works") }
            else { failures.append("restart failed") }
        } catch { failures.append("restart failed") }

        let console = session.events.compactMap { event -> String? in
            if case .console(let level, let message) = event { return "[\(level)] \(message)" }
            return nil
        }
        return RuntimeReport(passed: passed, failures: failures, console: console)
    }
}
