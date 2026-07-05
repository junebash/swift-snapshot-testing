import XCTest

@testable import SnapshotTesting

final class AsyncAssertSnapshotTests: BaseTestCase {
  @MainActor
  func testAsyncAssertSnapshot() async {
    await assertSnapshot(of: ["Hello", "World"], as: .dump)
  }

  @MainActor
  func testAsyncSnapshotStrategy() async {
    let strategy = Snapshotting<String, String>(
      pathExtension: "txt",
      diffing: .lines
    ) { value in
      await Task.yield()
      return value + ", World!"
    }
    await assertSnapshot(of: "Hello", as: strategy)
  }

  @MainActor
  func testAsyncPullback() async {
    let strategy = Snapshotting<String, String>.lines.pullback { (value: Int) async -> String in
      await Task.yield()
      return "\(value)"
    }
    await assertSnapshot(of: 42, as: strategy)
  }

  @MainActor
  func testMainActorRemainsResponsiveWhileAwaiting() async {
    let strategy = Snapshotting<String, String>(
      pathExtension: "txt",
      diffing: .lines
    ) { (value: String) async -> String in
      // This hop can only complete if the assertion suspends, rather than blocks, the main
      // actor while awaiting the snapshot.
      await MainActor.run { value }
    }
    await assertSnapshot(of: "main actor is free", as: strategy)
  }

  @MainActor
  func testAsyncVerifySnapshotTimeout() async {
    let never = Snapshotting<String, String>(
      pathExtension: "txt",
      diffing: .lines,
      asyncSnapshot: { _ in Async { _ in } }
    )
    let failure = await verifySnapshot(of: "Hello", as: never, timeout: 0.1)
    XCTAssertEqual(failure?.hasPrefix("Exceeded timeout of 0.1 seconds"), true)
  }

  func testAsyncValue() async {
    let async = Async<Int> { callback in callback(42) }
    let value = await async.value
    XCTAssertEqual(value, 42)
  }

  func testAsyncValueIgnoresExtraCallbacks() async {
    let async = Async<Int> { callback in
      callback(1)
      callback(2)
    }
    let value = await async.value
    XCTAssertEqual(value, 1)
  }

  func testAsyncOperationInit() async {
    let async = Async<Int>(operation: {
      await Task.yield()
      return 42
    })
    let value = await async.value
    XCTAssertEqual(value, 42)
  }
}
