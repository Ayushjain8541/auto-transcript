import Foundation
import LectureCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Expectation failed", file: StaticString = #filePath, line: UInt = #line) throws {
    if try !condition() { throw CheckFailure(description: "\(file):\(line): \(message)") }
}
func expectThrows(_ action: () throws -> Void, _ predicate: (Error) -> Bool = { _ in true }) throws {
    do { try action() } catch { try expect(predicate(error), "Unexpected error: \(error)"); return }
    throw CheckFailure(description: "Expected an error, but operation succeeded")
}
@MainActor enum Checks {
    static var cases: [(String, @MainActor () async throws -> Void)] = []
    static func add(_ name: String, _ body: @escaping @MainActor () async throws -> Void) { cases.append((name, body)) }
}
@main struct TestRunner {
    @MainActor static func main() async {
        registerCaptureTests()
        registerStorageTests()
        registerAudioTests()
        registerModelTests()
        registerTranscriptionTests()
        registerCoordinatorTests()
        let filter = CommandLine.arguments.dropFirst().first
        let selected = Checks.cases.filter { filter == nil || $0.0.range(of: filter!, options: .regularExpression) != nil }
        guard !selected.isEmpty else { print("No checks matched"); exit(2) }
        var failures = 0
        for (name, body) in selected {
            do { try await body(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(selected.count - failures)/\(selected.count) checks passed")
        exit(failures == 0 ? 0 : 1)
    }
}
