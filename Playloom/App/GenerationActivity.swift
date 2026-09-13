import Foundation

nonisolated struct GenerationActivity: Equatable, Sendable, Identifiable {
    let runID: RunID
    let events: [GenerationEvent]

    init?(events: [GenerationEvent]) {
        guard let latest = events.last else { return nil }
        let runEvents = events.filter { $0.runID == latest.runID }
        guard !runEvents.isEmpty else { return nil }
        self.runID = latest.runID
        self.events = runEvents
    }

    var id: RunID { runID }

    var latestEvent: GenerationEvent { events[events.count - 1] }

    var collapsedSummary: String {
        switch latestEvent.kind {
        case .completed: return "Playable"
        case .cancelled: return "Generation stopped"
        case .failed: return "Generation failed"
        case .staleCompletion: return "Stale result ignored"
        default: return latestEvent.summary
        }
    }

    var isActive: Bool {
        switch latestEvent.lifecycle {
        case .completed, .cancelled, .failed, .relaunchedInterrupted, .forceQuitUnknown:
            return false
        default:
            switch latestEvent.kind {
            case .completed, .cancelled, .failed, .staleCompletion: return false
            default: return true
            }
        }
    }

    var lifecycle: RunLifecycle? { latestEvent.lifecycle }

    var hasKeepOpenWarning: Bool { events.contains { $0.kind == .keepOpenWarning } }
}
