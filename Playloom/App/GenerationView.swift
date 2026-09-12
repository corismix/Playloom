import SwiftUI

struct GenerationView: View {
    @State private var model = GenerationModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let session = model.session {
                    GameWebView(session: session)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxHeight: .infinity)
                    TextField("Change the game", text: $model.edit)
                    Button("Apply edit") { Task { await model.applyEdit() } }.disabled(model.isWorking)
                } else {
                    Spacer()
                    Text("Describe a small game").font(.title2.bold())
                    TextField("Game prompt", text: $model.prompt, axis: .vertical).lineLimit(3...6)
                    SecureField("OpenRouter API key", text: $model.apiKey)
                    Button("Save key") { model.saveKey() }.disabled(model.apiKey.isEmpty)
                    Button("Generate game") { Task { await model.generate() } }.buttonStyle(.borderedProminent).disabled(model.isWorking)
                    Spacer()
                }
                if model.isWorking { ProgressView(model.status) } else { Text(model.status).font(.footnote).foregroundStyle(.secondary) }
            }
            .textFieldStyle(.roundedBorder)
            .buttonStyle(.borderedProminent)
            .padding()
            .navigationTitle("Playloom")
        }
    }
}
