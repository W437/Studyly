import Foundation

/// Where a new model gets its id: a random UUID, except inside `ModelID.seeded(_:_:)`, where ids come from a named
/// sequence ("demo#0", "demo#1", …). The demo world seeds inside one, so its ids are the same on every launch and
/// screenshots and films repeat exactly (the sky's layout and every tie-break by id depend on them). The sequence
/// is a task local, so a model made anywhere else at the same time still gets a random id.
enum ModelID {
    final class Sequence: @unchecked Sendable {
        let name: String
        var next = 0
        init(name: String) { self.name = name }
    }

    @TaskLocal static var sequence: Sequence?

    static func make() -> UUID {
        guard let sequence else { return UUID() }
        defer { sequence.next += 1 }
        return StableRandom.uuid("\(sequence.name)#\(sequence.next)")
    }

    /// Runs `body` with seeded ids.
    static func seeded<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        try $sequence.withValue(Sequence(name: name)) { try body() }
    }
}
