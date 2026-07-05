import XCTest

@testable import SnapshotTesting

/// Tests the opt-in settled-value check (`SNAPSHOT_TESTING_REQUIRE_SETTLED`): after an async
/// assertion passes, the value is captured again following one CoreAnimation commit, and the
/// assertion fails if the two captures differ.
final class RequireSettledTests: BaseTestCase {
  override func setUp() {
    super.setUp()
    requireSettledSnapshotsOverride = true
  }

  override func tearDown() {
    requireSettledSnapshotsOverride = nil
    super.tearDown()
  }

  @MainActor
  func testSettledValuePasses() async {
    await assertSnapshot(of: "stable", as: .lines)
  }

  @MainActor
  func testUnsettledValueFails() async {
    let subject = Subject(value: "before")
    DispatchQueue.main.async { subject.value = "after" }
    let failure = await verifySnapshot(of: subject, as: .subjectValue, timeout: 1)
    XCTAssertEqual(failure?.contains("was not settled") == true, true, failure ?? "no failure")
  }

  @MainActor
  func testUnsettledValueFailsInMultiStrategyAssertion() async {
    let subject = Subject(value: "before")
    DispatchQueue.main.async { subject.value = "after" }
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { $0.compactDescription.contains("was not settled") }
    XCTExpectFailure("the value mutates after the captures", options: options)
    await assertSnapshots(of: subject, as: ["only": .subjectValue])
  }
}

private final class Subject {
  var value: String
  init(value: String) {
    self.value = value
  }
}

extension Snapshotting where Value == Subject, Format == String {
  fileprivate static var subjectValue: Snapshotting {
    Snapshotting(pathExtension: "txt", diffing: .lines) { $0.value }
  }
}
