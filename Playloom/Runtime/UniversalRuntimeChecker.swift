import Foundation

@MainActor
struct UniversalRuntimeChecker {
    func run(session: GameRuntimeSession) async -> RuntimeReport {
        var passed: [String] = []
        var failures: [String] = []

        // The game-ready event itself proves the bridge. The document-start diagnostic
        // message can race with WebKit handler activation on newer OS versions, so retain
        // it as diagnostic metadata rather than making it a seventh acceptance check.
        if await session.waitFor({ $0 == .bridgeReady || $0 == .ready }, timeout: .seconds(15)) { passed.append("WebKit bridge ready") }

        if await session.waitFor({ $0 == .ready }, timeout: .seconds(15)) { passed.append("loads") }
        else { failures.append("game ready timeout: " + session.startupDiagnostic) }

        let fatal = session.events.compactMap { event -> String? in
            if case .fatal(let message) = event { return message }
            if case .console(let level, let message) = event, level == "error" { return message }
            return nil
        }
        if fatal.isEmpty { passed.append("no JavaScript crash") }
        else { failures.append("JavaScript: " + fatal.joined(separator: "; ")) }

        // `ready` may precede final SwiftUI layout and the first stable WebGL frame on device.
        try? await ContinuousClock().sleep(for: .seconds(2))

        do {
            let pixels = try await session.sampleVisiblePixels()
            if pixels.isNonBlank { passed.append("canvas not blank") }
            else { failures.append("blank canvas") }
        } catch { failures.append("pixel sample failed: \(error.localizedDescription)") }

        let initialFrames = session.events.filter { if case .heartbeat = $0 { true } else { false } }.count
        let advanced = await session.waitForHeartbeat(after: initialFrames, timeout: .seconds(3))
        if advanced { passed.append("heartbeat alive") }
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

        if !failures.isEmpty {
            let diagnostic = await session.diagnosticSnapshot()
            print("PLAYLOOM_RUNTIME_DIAGNOSTIC \(diagnostic)")
            failures.append("runtime diagnostic: " + diagnostic)
        }

        let console = session.events.compactMap { event -> String? in
            if case .console(let level, let message) = event { return "[\(level)] \(message)" }
            return nil
        }
        return RuntimeReport(passed: passed, failures: failures, console: console)
    }
}
