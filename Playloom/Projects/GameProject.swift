import Foundation

nonisolated struct GameProject: Codable, Equatable, Sendable {
    var title: String
    var files: [String: String]

    func validated() throws -> GameProject {
        let required = Set(["index.html", "game.js", "style.css"])
        guard required.isSubset(of: Set(files.keys)) else { throw GameProjectError.missingRequiredFile }
        guard files.keys.allSatisfy(Self.isSafePath) else { throw GameProjectError.unsafePath }
        guard files.values.reduce(0, { $0 + $1.utf8.count }) <= 512_000 else { throw GameProjectError.tooLarge }
        guard files["index.html"]?.contains("phaser.min.js") == true else { throw GameProjectError.missingPhaser }
        return self
    }

    private static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("..") && !path.contains("\\") && !path.contains(":")
            && ["html", "js", "css", "json"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}

nonisolated enum GameProjectError: Error, Equatable { case missingRequiredFile, unsafePath, tooLarge, missingPhaser }
