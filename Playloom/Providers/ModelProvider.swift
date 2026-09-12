import Foundation

nonisolated protocol ModelProvider: Sendable {
    func generateProject(prompt: String) async throws -> GameProject
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject
}
