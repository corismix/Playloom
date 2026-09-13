import SwiftUI

/// A replayed, app-owned activity surface. It deliberately receives typed
/// GenerationEvent values rather than provider text or a progress percentage.
struct ActivityCard: View {
    let activity: GenerationActivity
    let onStop: (() -> Void)?
    @State private var isExpanded = false

    init(activity: GenerationActivity, onStop: (() -> Void)? = nil) {
        self.activity = activity
        self.onStop = onStop
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(activity.events) { event in
                    eventRow(event)
                }
                if activity.isActive, let onStop {
                    Button("Stop") { onStop() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("generation.activity.stop")
                }
            }
            .padding(.top, 8)
            .accessibilityIdentifier("generation.activity.details")
        } label: {
            HStack(spacing: 8) {
                if activity.isActive { ProgressView().controlSize(.small) }
                Text(activity.collapsedSummary)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("generation.activity.summary")
                Spacer(minLength: 8)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("generation.activity.card")
    }

    @ViewBuilder
    private func eventRow(_ event: GenerationEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                MarkdownSummaryView(markdown: event.summary)
                    .font(.footnote.weight(.medium))
            }
            if let detail = event.detail, !detail.isEmpty {
                MarkdownSummaryView(markdown: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 62)
            }
            eventFacts(event)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generation.activity.event.\(event.id.uuidString)")
    }

    @ViewBuilder
    private func eventFacts(_ event: GenerationEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let check = event.check {
                Text("Check: \(check.summary) — \(check.status.rawValue)")
            }
            if let fileDiff = event.fileDiff {
                Text("Files: +\(fileDiff.added.count), changed \(fileDiff.changed.count), −\(fileDiff.removed.count)")
            }
            if let retryRound = event.retryRound {
                Text("Retry round \(retryRound)")
            }
            if let duration = event.durationMilliseconds {
                Text("Duration: \(duration) ms")
            }
            if let usage = event.usage {
                usageSummary(usage)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.leading, 62)
    }

    @ViewBuilder
    private func usageSummary(_ usage: UsageSummary) -> some View {
        let values = [
            usage.inputTokens.map { "in \($0)" },
            usage.outputTokens.map { "out \($0)" },
            usage.totalTokens.map { "total \($0)" },
            usage.costMicros.map { "cost \($0)μ" }
        ].compactMap { $0 }
        if !values.isEmpty {
            Text("Usage: \(values.joined(separator: ", "))")
        }
    }
}
