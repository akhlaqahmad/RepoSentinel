import Foundation

/// Everything a scanner needs to talk to the engine. All closures are safe to call from any thread.
struct Ctx: Sendable {
    let log: @Sendable (LogLevel, String) -> Void
    let found: @Sendable (Finding) -> Void
    let progress: @Sendable (_ done: Int, _ total: Int, _ detail: String) -> Void
    let active: @Sendable (_ item: String, _ on: Bool) -> Void
    /// Throws CancellationError when stopped; suspends while paused.
    let checkpoint: @Sendable () async throws -> Void
    var skipDirs: Set<String> = IOC.defaultSkip
    var roots: [URL] = [URL(fileURLWithPath: NSHomeDirectory())]
    var concurrency = 6
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    @discardableResult func inc() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func reset() { lock.lock(); n = 0; lock.unlock() }
}

func forEachConcurrent<T: Sendable>(_ items: [T], limit: Int, _ body: @escaping @Sendable (T) async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { g in
        var it = items.makeIterator()
        func add() { if let x = it.next() { g.addTask { try await body(x) } } }
        for _ in 0..<max(1, limit) { add() }
        while try await g.next() != nil { add() }
    }
}
