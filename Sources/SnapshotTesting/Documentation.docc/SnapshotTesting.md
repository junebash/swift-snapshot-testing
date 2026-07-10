# ``SnapshotTesting``

Delightfully powerful snapshot testing.

## Overview

Snapshot testing captures a value — a view, an image, a network request, an encodable model — and
compares it against a reference saved on disk, failing the test when the two disagree. It works for
practically any value, not just user interfaces.

```swift
import SnapshotTesting
import Testing

@Test @MainActor func greeting() async {
  await assertSnapshot(of: ["Hello", "Bonjour", "Hola"], as: .dump())
}
```

The first time this runs, ``assertSnapshot(of:as:named:record:snapshotDirectory:timeout:fileID:file:testName:line:column:)``
has nothing to compare against, so it writes a reference file next to the test (in a
`__Snapshots__` directory) and fails, prompting you to review and commit the reference. Every
subsequent run captures the value again and compares it to that reference, failing only when they
differ.

### `@MainActor` and `async`

`assertSnapshot`, `assertSnapshots`, and ``verifySnapshot(of:as:named:record:snapshotDirectory:timeout:fileID:file:testName:line:column:)``
are all `@MainActor` and `async`. Most built-in strategies capture their value synchronously under
the hood, so calling from a `@MainActor` test runs the capture eagerly, in the same run-loop turn
as the call — before any queued main-actor work (a pending layout pass, an animation callback) can
mutate the value out from under you. Only strategies that are genuinely asynchronous (a `WKWebView`
waiting to finish loading, say) actually suspend. Use the `timeout` parameter to bound how long an
asynchronous capture may take.

### Record modes

Whether a missing or mismatching snapshot gets written to disk is controlled by a
``SnapshotTestingConfiguration/Record`` mode:

- ``SnapshotTestingConfiguration/Record/missing`` records only snapshots that don't yet exist on
  disk. This is the default, and the one you want on CI.
- ``SnapshotTestingConfiguration/Record/failed`` re-records a snapshot whenever the assertion
  fails. Handy when a precision threshold makes small, expected drift show up as a failure.
- ``SnapshotTestingConfiguration/Record/all`` unconditionally (re-)records every snapshot it sees.
- ``SnapshotTestingConfiguration/Record/never`` never records; a missing reference is a failure.

Set the mode for a whole test, suite, or scope with the `.snapshots` trait (Swift Testing) or
``withSnapshotTesting(record:diffTool:operation:)``:

```swift
@Test(.snapshots(record: .missing))
func greeting() async {
  await assertSnapshot(of: "Hello", as: .lines)
}
```

```swift
await withSnapshotTesting(record: .all) {
  await assertSnapshot(of: "Hello", as: .lines)
}
```

Absent either of those, the `SNAPSHOT_TESTING_RECORD` environment variable is consulted, and
finally the mode falls back to ``SnapshotTestingConfiguration/Record/missing``.

## Topics

### Essentials

- ``assertSnapshot(of:as:named:record:snapshotDirectory:timeout:fileID:file:testName:line:column:)``
- ``verifySnapshot(of:as:named:record:snapshotDirectory:timeout:fileID:file:testName:line:column:)``
- <doc:CustomStrategies>

### Strategy protocols

- ``SnapshotStrategy``
- ``DiffStrategy``
- ``SnapshotDifference``
- ``SnapshotAttachment``

### Value strategies

- ``LinesStrategy``
- ``RawDataStrategy``
- ``LinesDiffing``
- ``DataDiffing``
- ``AnySnapshotStringConvertible``

### View & image strategies

Rendering a view or view controller to an image is platform-specific: on iOS and tvOS it's
`UIViewImageStrategy`, `UIViewControllerImageStrategy`, and `SwiftUIViewImageStrategy` (configured
by `SwiftUISnapshotLayout`), diffing through `UIImageDiffing`/`UIImageStrategy` and sized with
`ViewImageConfig`; on macOS it's `NSViewImageStrategy` and `NSViewControllerImageStrategy`, diffing
through `NSImageDiffing`/`NSImageStrategy`. Each exposes the same `.image` (and `.image(…:)`)
static member on ``SnapshotStrategy``.

### Scene strategies

- ``SCNSceneImageStrategy``
- ``SKSceneImageStrategy``

### Configuration

- ``withSnapshotTesting(record:diffTool:operation:)``
- ``withSnapshotTesting(record:diffTool:isolation:operation:)``
- ``SnapshotTestingConfiguration``
- ``Testing/Trait/snapshots``
- ``Testing/Trait/snapshots(record:diffTool:)``
- ``Testing/Trait/snapshots(_:)``

### Timeouts

- ``withDeadline(in:clock:operation:)``
- ``DeadlineExceededError``
