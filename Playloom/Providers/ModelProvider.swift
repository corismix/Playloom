import Foundation

nonisolated protocol ModelProvider: Sendable {
    var displayName: String { get }
    func generateProject(prompt: String) async throws -> GameProject
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject
}
