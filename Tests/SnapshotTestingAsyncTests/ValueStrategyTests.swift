import Foundation
import Testing

@testable import SnapshotTestingAsync

private struct User {
  var id: Int
  var name: String
}

@Suite @MainActor struct ValueStrategyTests {
  @Test func descriptionMatches() async throws {
    let user = User(id: 1, name: "Blobby")
    let diff = try await _verifySnapshot(
      of: user, as: .description(),
      reference: Data(String(describing: user).utf8))
    #expect(diff == nil)
  }

  @Test func dumpProducesStableTree() async throws {
    let user = User(id: 1, name: "Blobby")
    let recorded = await _recordSnapshot(of: user, as: .dump())
    let text = String(decoding: recorded, as: UTF8.self)
    #expect(text.contains("▿ User"))
    #expect(text.contains("- id: 1"))
    #expect(text.contains("- name: \"Blobby\""))
  }

  @Test func jsonSortsKeysAndSetsExtension() async throws {
    let object: [String: Any] = ["b": 2, "a": 1]
    let strategy: _PathExtension<_Pullback<[String: Any], LinesStrategy>> = .json()
    #expect(strategy.pathExtension == "json")
    let recorded = await _recordSnapshot(of: object, as: strategy)
    let text = String(decoding: recorded, as: UTF8.self)
    // sortedKeys => "a" before "b"
    #expect(text.range(of: "\"a\"")!.lowerBound < text.range(of: "\"b\"")!.lowerBound)
  }
}
