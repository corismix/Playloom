import SwiftUI
import Textual

/// Renders curated, consumer-facing assistant and activity summaries.
/// Provider chain-of-thought never enters this view or the persisted activity model.
struct MarkdownSummaryView: View {
    let markdown: String

    var body: some View {
        StructuredText(markdown: markdown)
            .textual.structuredTextStyle(.default)
    }
}
