# Defining custom snapshot strategies

Extend SnapshotTesting to new value types, formats, and comparisons with the ``SnapshotStrategy``
and ``DiffStrategy`` protocols.

## Overview

A snapshot assertion is built from two collaborating protocols:

- ``SnapshotStrategy`` knows how to capture a `Value` (a view, a request, a model) into a
  diffable `Format` (an image, a string, raw bytes).
- ``DiffStrategy`` knows how to serialize that `Format` to and from disk, and how to compare two
  instances of it.

Most of the time you don't write either from scratch — you derive a new ``SnapshotStrategy`` from
an existing one.

## Deriving a strategy with `pullback`

``SnapshotStrategy/pullback(_:)`` adapts an existing strategy to a new `Value` type by transforming
into the type the strategy already knows how to capture. Given the built-in image strategy for
`UIView`:

```swift
extension SnapshotStrategy where Self == UIViewImageStrategy {
  public static var image: UIViewImageStrategy { UIViewImageStrategy() }
}
```

a strategy for `UIViewController` can pull back to it by projecting out the controller's view:

```swift
extension SnapshotStrategy where Self == _Pullback<UIViewController, UIViewImageStrategy> {
  static var image: Self {
    UIViewImageStrategy().pullback { $0.view }
  }
}
```

The transform runs on `@MainActor`, so it's safe to touch main-actor-isolated state (reading a
controller's `view`, for instance). On a `@MainActor` caller — which every assertion is — it runs
eagerly with no thread hop.

## Asynchronous captures with `asyncPullback`

Some values can only be captured asynchronously — a web view that must finish loading first, for
example. ``SnapshotStrategy/asyncPullback(_:)`` is like `pullback`, but its transform is itself
`async`:

```swift
extension SnapshotStrategy where Self == _AsyncPullback<WKWebView, UIImageStrategy> {
  static var image: Self {
    UIImageStrategy().asyncPullback { webView in
      await webView.yourOwnAsyncSnapshot()  // e.g. wrapping `takeSnapshot(with:completionHandler:)`
    }
  }
}
```

``withDeadline(in:clock:operation:)`` races an async operation against a timer and throws
``DeadlineExceededError`` if the timer wins. It's a general-purpose building block, not something
the transform above needs — the assertion's own `timeout` parameter already bounds the whole
capture, `WKWebView` included. Reach for `withDeadline` when a custom strategy performs async work
of its own that the assertion's timeout doesn't cover, such as fetching a reference over the
network:

```swift
struct RemoteJSONStrategy: SnapshotStrategy {
  var pathExtension: String? { "json" }
  var diffing: LinesDiffing { LinesDiffing() }

  func snapshot(of url: sending URL) async -> sending String {
    let url = url  // `withDeadline`'s operation is `@Sendable`; re-bind out of `sending`.
    guard
      let data = try? await withDeadline(in: .seconds(5), operation: {
        (try? await URLSession.shared.data(from: url).0) ?? Data()
      })
    else { return "<timed out>" }
    return String(decoding: data, as: UTF8.self)
  }
}
```

`operation` is `@Sendable`, so it can only capture `Sendable` values — `URL` qualifies, but a
non-`Sendable` reference like a view would not.

## Writing a strategy from scratch

When there's no existing strategy to pull back from, conform to ``SnapshotStrategy`` directly. The
requirement, ``SnapshotStrategy/snapshot(of:)``, is `nonisolated(nonsending)`: it runs on whatever
executor the caller is already on rather than hopping to a fixed one. A pure value strategy (no
main-actor state involved) can satisfy this with a plain synchronous function:

```swift
struct FirstLineStrategy: SnapshotStrategy {
  var pathExtension: String? { "txt" }
  var diffing: LinesDiffing { LinesDiffing() }

  func snapshot(of value: sending String) -> sending String {
    value.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
  }
}
```

A strategy that touches view or window state should mark `snapshot(of:)` `@MainActor` instead, the
same way the built-in `UIViewImageStrategy` and `NSViewImageStrategy` do — that's what gives
callers on the main actor an eager, non-hopping capture.

## Writing a diffing strategy

``DiffStrategy`` is the serialization and comparison half. Its three requirements are deliberately
synchronous — a diffing strategy never touches the main actor or awaits, so it composes freely
underneath any ``SnapshotStrategy``:

```swift
struct CaseInsensitiveDiffing: DiffStrategy {
  func data(from value: String) -> Data { Data(value.utf8) }
  func value(from data: Data) throws -> String { String(decoding: data, as: UTF8.self) }

  func diff(_ reference: String, _ candidate: String) -> SnapshotDifference? {
    guard reference.lowercased() != candidate.lowercased() else { return nil }
    return SnapshotDifference(message: "Expected \(candidate) to match \(reference)")
  }
}
```

Return `nil` from ``DiffStrategy/diff(_:_:)`` when the two values match. Otherwise return a
``SnapshotDifference`` with a human-readable message and any ``SnapshotAttachment``s (a reference
image, a failure image, a text patch) worth surfacing alongside the test failure.

## Overriding the path extension

``SnapshotStrategy/pathExtension(_:)`` replaces just the file extension used for the on-disk
reference, leaving capture and diffing untouched — useful when a pulled-back strategy's default
extension doesn't fit:

```swift
extension SnapshotStrategy where Self == _PathExtension<_Pullback<MyModel, LinesStrategy>> {
  static var summary: Self {
    LinesStrategy().pullback { $0.summary }.pathExtension("summary.txt")
  }
}
```
