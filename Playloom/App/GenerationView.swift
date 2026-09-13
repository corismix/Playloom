import SwiftUI

struct GenerationView: View {
    @State private var model = GenerationModel()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: Field?

    private enum Field { case prompt, key, edit }

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ScrollView {
                VStack(spacing: 12) {
                    if let checking = model.candidateSession {
                        ZStack {
                            GameWebView(session: checking)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .frame(height: gameHeight(in: geometry.size.height))
                            Rectangle().fill(.background.opacity(0.35)).allowsHitTesting(true)
                            ProgressView("Checking generated game")
                                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else if let session = model.session {
                        GameWebView(session: session)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(height: gameHeight(in: geometry.size.height))
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
                    activityView
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
                .task {
                    await model.restoreOnLaunch(as: AppDelegate.launchRecoveryReason)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.didBecomeActive() }
                    else if phase == .background { model.didEnterBackground() }
                }
            }
        }
    }

    @ViewBuilder private var activityView: some View {
        if let activity = GenerationActivity(events: model.events) {
            ActivityCard(activity: activity, onStop: model.isWorking ? { model.stop() } : nil)
            if model.isWorking {
                Button("Stop generation") { model.stop() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("generation.stop")
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.status).font(.headline)
                if !model.detail.isEmpty { Text(model.detail).font(.footnote).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gameHeight(in availableHeight: CGFloat) -> CGFloat {
        max(360, availableHeight * 0.68)
    }

    private func dismissKeyboard() { focusedField = nil }
    private func startGeneration() { Task { await model.generate() } }
    private func startEdit() { Task { await model.applyEdit() } }
}
