import Foundation

nonisolated enum RuntimeEvent: Equatable, Sendable {
    case ready
    case heartbeat(Int)
    case inputReceived
    case restarted
    case console(level: String, message: String)
    case fatal(String)

    init?(message: Any) {
        guard let value = message as? [String: Any], let type = value["type"] as? String else { return nil }
        switch type {
        case "ready": self = .ready
        case "heartbeat": self = .heartbeat(value["frame"] as? Int ?? 0)
        case "input": self = .inputReceived
        case "restarted": self = .restarted
        case "console": self = .console(level: value["level"] as? String ?? "log", message: value["message"] as? String ?? "")
        case "fatal": self = .fatal(value["message"] as? String ?? "Unknown JavaScript error")
        default: return nil
        }
    }
}

nonisolated struct RuntimeReport: Equatable, Sendable {
    var passed: [String]
    var failures: [String]
    var console: [String]
    var isPassing: Bool { failures.isEmpty }
}

nonisolated struct PixelSample: Codable, Equatable, Sendable {
    let changedRatio: Double
    let width: Int
    let height: Int
    var isNonBlank: Bool { changedRatio >= 0.01 }
}

nonisolated enum RuntimeCheckState: Equatable, Sendable {
    case idle
    case running
    case passed(RuntimeReport)
    case failed(RuntimeReport)
}
