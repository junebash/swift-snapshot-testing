import XCTest

@testable import SnapshotTesting

/// Tests the eager-capture guarantee of the async assertion overloads: every snapshot operation
/// is started before the assertion's first suspension point, so work queued on the main run loop
/// cannot mutate the value before it is captured.
final class EagerCaptureTests: BaseTestCase {
  @MainActor
  func testCapturesBeforeFirstSuspensionPoint() async {
    let subject = Subject(value: "before")
    DispatchQueue.main.async { subject.value = "after" }
    await assertSnapshot(of: subject, as: .subjectValue)
  }

  @MainActor
  func testDictionaryOfStrategiesCapturesBeforeFirstSuspensionPoint() async {
    let subject = Subject(value: "before")
    DispatchQueue.main.async { subject.value = "after" }
    await assertSnapshots(of: subject, as: ["first": .subjectValue, "second": .subjectValue])
  }

  @MainActor
  func testArrayOfStrategiesCapturesBeforeFirstSuspensionPoint() async {
    let subject = Subject(value: "before")
    DispatchQueue.main.async { subject.value = "after" }
    await assertSnapshots(of: subject, as: [.subjectValue, .subjectValue])
  }

  @MainActor
  func testAsynchronousStrategiesStartBeforeEarlierStrategiesFinish() async {
    var firstFinished = false
    var secondStartedBeforeFirstFinished: Bool?
    let first = Snapshotting<String, String>(
      pathExtension: "txt",
      diffing: .lines,
      asyncSnapshot: { value in
        Async { callback in
          DispatchQueue.main.async {
            firstFinished = true
            callback(value)
          }
        }
      }
    )
    let second = Snapshotting<String, String>(
      pathExtension: "txt",
      diffing: .lines,
      asyncSnapshot: { value in
        Async { callback in
          secondStartedBeforeFirstFinished = !firstFinished
          DispatchQueue.main.async { callback(value) }
        }
      }
    )
    await assertSnapshots(of: "concurrent", as: ["first": first, "second": second])
    XCTAssertEqual(secondStartedBeforeFirstFinished, true)
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
