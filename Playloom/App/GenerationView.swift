import SwiftUI

struct GenerationView: View {
    @State private var model = GenerationModel()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: Field?

    private enum Field { case prompt, key, edit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let session = model.session {
                        GameWebView(session: session)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(minHeight: 360)
                        TextField("Change the game", text: $model.edit)
                            .focused($focusedField, equals: .edit)
                            .submitLabel(.done)
                            .onSubmit { dismissKeyboard(); startEdit() }
                        Button("Apply edit") { dismissKeyboard(); startEdit() }.disabled(model.isWorking)
                    } else {
                        Spacer(minLength: 80)
                        Text("Describe a small game").font(.title2.bold())
                        TextField("Game prompt", text: $model.prompt, axis: .vertical)
                            .lineLimit(3...6).focused($focusedField, equals: .prompt)
                            .submitLabel(.done).onSubmit { dismissKeyboard() }
                        SecureField(model.apiKeyLabel, text: $model.apiKey)
                            .focused($focusedField, equals: .key)
                            .textContentType(.password).submitLabel(.done)
                            .onSubmit { dismissKeyboard(); model.saveKey() }
                        Button("Save key") { dismissKeyboard(); model.saveKey() }.disabled(model.apiKey.isEmpty)
                        Button("Generate game") { dismissKeyboard(); startGeneration() }
                            .buttonStyle(.borderedProminent).disabled(model.isWorking)
                        Spacer(minLength: 80)
                    }
                    statusView
                }
                .frame(maxWidth: .infinity)
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
            }
            .scrollDismissesKeyboard(.interactively)
            .textFieldStyle(.roundedBorder)
            .buttonStyle(.borderedProminent)
            .navigationTitle("Playloom")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.didBecomeActive() }
                else if phase == .background { model.didEnterBackground() }
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { if model.isWorking { ProgressView() }; Text(model.status).font(.headline) }
            if !model.detail.isEmpty { Text(model.detail).font(.footnote).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dismissKeyboard() { focusedField = nil }
    private func startGeneration() { Task { await model.generate() } }
    private func startEdit() { Task { await model.applyEdit() } }
}
