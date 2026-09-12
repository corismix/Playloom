import SwiftUI

struct RuntimeSpikeView: View {
    @State private var model = RuntimeSpikeModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GameWebView(session: model.session)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.25))
                    }
                    .frame(maxHeight: .infinity)

                status

                HStack {
                    Button("Run checks") { Task { await model.runChecks() } }
                        .buttonStyle(.borderedProminent)
                    Button("Restart") { model.restart() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Runtime spike")
            .task { model.start() }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .idle: Text("Preparing runtime")
        case .running: ProgressView("Checking game")
        case .passed(let report): Label("Passed \(report.passed.count) checks", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let report): Label(report.failures.joined(separator: ", "), systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
