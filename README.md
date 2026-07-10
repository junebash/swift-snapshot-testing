# 📸 SnapshotTesting

[![CI](https://github.com/junebash/swift-snapshot-testing/actions/workflows/ci.yml/badge.svg)](https://github.com/junebash/swift-snapshot-testing/actions/workflows/ci.yml)

Delightful Swift snapshot testing.

> **This is a personal fork.** This repository is [June Bash](https://github.com/junebash)'s
> hard fork of [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing),
> the excellent library created by [Point-Free](https://www.pointfree.co). All credit for the
> original design goes to them; see [Learn More](#learn-more) below. This fork has diverged
> significantly from upstream and is **not** a drop-in replacement:
>
>   - The public API is **async-only**. `assertSnapshot`, `assertSnapshots`, `verifySnapshot`, and
>     `assertInlineSnapshot` are all `@MainActor` and `async` — every call site must `await`. There
>     is no synchronous overload.
>   - The closure-based `Snapshotting<Value, Format>` witness type is gone, replaced by real Swift
>     protocols (`SnapshotStrategy`, `DiffStrategy`) with native structured-concurrency support.
>   - The toolchain floor is **Swift 6.2+**, built in the Swift 6 language mode.
>
> If you depend on the upstream, synchronous API, use
> [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
> instead.

## Usage

Once [installed](#installation), _no additional configuration is required_. Import the
`SnapshotTesting` module and `await` the `assertSnapshot` function from an async test.

With [Swift Testing](https://developer.apple.com/documentation/testing):

``` swift
import SnapshotTesting
import Testing

@MainActor
struct MyViewControllerTests {
  @Test func myViewController() async {
    let vc = MyViewController()

    await assertSnapshot(of: vc, as: .image)
  }
}
```

Or with XCTest:

``` swift
import SnapshotTesting
import XCTest

final class MyViewControllerTests: XCTestCase {
  @MainActor
  func testMyViewController() async {
    let vc = MyViewController()

    await assertSnapshot(of: vc, as: .image)
  }
}
```

When an assertion first runs, a snapshot is automatically recorded to disk and the test will fail,
printing out the file path of any newly-recorded reference.

> ❌ failed - No reference was found on disk. Automatically recorded snapshot: …
>
> open "…/MyAppTests/\_\_Snapshots\_\_/MyViewControllerTests/testMyViewController.png"
>
> Re-run "testMyViewController" to test against the newly-recorded snapshot.

Repeat test runs will load this reference and compare it with the runtime value. If they don't
match, the test will fail and describe the difference. Failures can be inspected from Xcode's Report
Navigator or by inspecting the file URLs of the failure.

You can record a new reference by customizing snapshots inline with the assertion, or using the
`withSnapshotTesting` tool:

```swift
// Record just this one snapshot
await assertSnapshot(of: vc, as: .image, record: .all)

// Record all snapshots in a scope:
await withSnapshotTesting(record: .all) {
  await assertSnapshot(of: vc1, as: .image)
  await assertSnapshot(of: vc2, as: .image)
  await assertSnapshot(of: vc3, as: .image)
}

// Record all snapshot failures in a Swift Testing suite:
@Suite(.snapshots(record: .failed))
struct FeatureTests {}

// Record all snapshot failures in an 'XCTestCase' subclass:
class FeatureTests: XCTestCase {
  override func invokeTest() {
    withSnapshotTesting(record: .failed) {
      super.invokeTest()
    }
  }
}
```

## Snapshot Anything

While most snapshot testing libraries in the Swift community are limited to `UIImage`s of `UIView`s,
SnapshotTesting can work with _any_ format of _any_ value on _any_ Swift platform!

The `assertSnapshot` function accepts a value and any snapshot strategy that value supports. This
means that a view or view controller can be tested against an image representation _and_ against a
textual representation of its properties and subview hierarchy.

``` swift
await assertSnapshot(of: vc, as: .image)
await assertSnapshot(of: vc, as: .recursiveDescription)
```

View controller image and recursive-description snapshots are configurable with device presets,
sizes, and trait collections, so you can generate device-agnostic snapshots from a single simulator.

``` swift
await assertSnapshot(of: vc, as: .image(on: .iPhoneSe))
await assertSnapshot(of: vc, as: .recursiveDescription(on: .iPhoneSe))

await assertSnapshot(of: vc, as: .image(on: .iPhoneSe(.landscape)))
await assertSnapshot(of: vc, as: .recursiveDescription(on: .iPhoneSe(.landscape)))

await assertSnapshot(of: vc, as: .image(on: .iPhoneX))
await assertSnapshot(of: vc, as: .recursiveDescription(on: .iPhoneX))

await assertSnapshot(of: vc, as: .image(on: .iPadMini(.portrait)))
await assertSnapshot(of: vc, as: .recursiveDescription(on: .iPadMini(.portrait)))
```

> **Warning**
> Snapshots must be compared using the exact same simulator that originally took the reference to
> avoid discrepancies between images.

Better yet, SnapshotTesting isn't limited to views and view controllers! There are a number of
available snapshot strategies to choose from.

For example, you can snapshot test URL requests (_e.g._, those that your API client prepares).

``` swift
await assertSnapshot(of: urlRequest, as: .raw)
// POST http://localhost:8080/account
// Cookie: pf_session={"userId":"1"}
//
// email=blob%40pointfree.co&name=Blob
```

And you can snapshot test `Encodable` values against their JSON _and_ property list representations.

``` swift
await assertSnapshot(of: user, as: .json())
// {
//   "bio" : "Blobbed around the world.",
//   "id" : 1,
//   "name" : "Blobby"
// }

await assertSnapshot(of: user, as: .plist())
// <?xml version="1.0" encoding="UTF-8"?>
// <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
//  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
// <plist version="1.0">
// <dict>
//   <key>bio</key>
//   <string>Blobbed around the world.</string>
//   <key>id</key>
//   <integer>1</integer>
//   <key>name</key>
//   <string>Blobby</string>
// </dict>
// </plist>
```

In fact, _any_ value can be snapshot-tested by default using its
[mirror](https://developer.apple.com/documentation/swift/mirror)!

``` swift
await assertSnapshot(of: user, as: .dump())
// ▿ User
//   - bio: "Blobbed around the world."
//   - id: 1
//   - name: "Blobby"
```

If your data can be represented as an image, text, or data, you can write a snapshot test for it!

## A tour of the built-in strategies

  - **Views and layers** (`UIView`/`UIViewController` on iOS/tvOS, `NSView`/`NSViewController` on
    macOS, `CALayer`): `.image` and `.recursiveDescription`; `UIViewController` additionally has
    `.hierarchy`. Every image strategy takes `precision`/`perceptualPrecision` overrides; on
    iOS/tvOS they additionally take `size` and `traits` overrides, and `UIViewController`'s
    `.image`/`.recursiveDescription` also take an `on:` device config — macOS has no trait
    collection or device-config equivalent. A `WKWebView` nested anywhere in the hierarchy is
    awaited automatically before the image is captured — this path is only expected to work in an
    app-hosted test runner, not a library/framework test bundle.
  - **SwiftUI views** (iOS/tvOS): `.image(layout:)`, rendered through a `UIHostingController`, with
    `.sizeThatFits`, `.fixed(width:height:)`, or `.device(config:)` layout options.
  - **SceneKit and SpriteKit** (`SCNScene`, `SKScene`): `.image(size:)`. Output is GPU/machine
    dependent, so recorded references don't transfer between machines.
  - **Paths** (`CGPath`, `UIBezierPath`/`NSBezierPath`): `.image` and `.elementsDescription`.
  - **`URLRequest`**: `.raw` (and `.raw(pretty:)`) for the request line, headers, and body; `.curl`
    for an equivalent cURL invocation.
  - **`Encodable` values**: `.json()`/`.json(_:)` and `.plist()`/`.plist(_:)`, each optionally taking
    a custom `JSONEncoder`/`PropertyListEncoder`.
  - **Any value**: `.description()` (via `String(describing:)`), `.dump()` (a sanitized, sorted
    `Mirror` dump), and `.json()` for any JSON-object-representable value.
  - **`String`**: `.lines`, comparing by line diff.
  - **`Data`**: `.data`, comparing by byte equality.
  - **Functions over `CaseIterable` inputs**: `.func(into:)` feeds every case into a
    `(Input) -> Output` function and records a CSV of input/output pairs.
  - **`customDump()`**, from the separate `SnapshotTestingCustomDump` product, renders any value with
    [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump)'s `customDump`.

You can also [write your own strategies](#writing-your-own-strategies) by conforming to
`SnapshotStrategy`, or derive new ones from existing strategies with `pullback`/`asyncPullback`.

## Writing your own strategies

A `SnapshotStrategy` knows how to render a `Value` into a diffable `Format`, and pairs that with a
`DiffStrategy` that knows how to serialize, deserialize, and compare that `Format`:

```swift
public protocol SnapshotStrategy<Value, Format> {
  associatedtype Value
  associatedtype Format
  associatedtype Diffing: DiffStrategy where Diffing.Value == Format

  var pathExtension: String? { get }
  var diffing: Diffing { get }

  nonisolated(nonsending) func snapshot(of value: sending Value) async -> sending Format
}
```

`snapshot(of:)` requires `nonisolated(nonsending)`, meaning it runs on the *caller's* executor rather
than hopping to a fixed one. Most view/image strategies are `@MainActor` witnesses of this
requirement: when the assertion is called from `@MainActor` code (as it always is), the capture's
synchronous prefix runs eagerly in the caller's run-loop turn, before any queued main-actor work can
mutate the value — and the witness only truly suspends for a genuinely asynchronous capture (like a
web view waiting to finish loading).

Rather than writing a strategy from scratch, you can often derive one from an existing strategy:

```swift
extension SnapshotStrategy where Self == _Pullback<MyModel, LinesStrategy> {
  static var summary: _Pullback<MyModel, LinesStrategy> {
    LinesStrategy().pullback { (model: MyModel) in model.summary }
  }
}
```

Use `asyncPullback` instead of `pullback` when the transform itself needs to `await` (for example,
when it renders a view that suspends on a web or scene subview before handing off to a base
strategy).

## Installation

SnapshotTesting is distributed via the [Swift Package Manager](https://swift.org/package-manager/).
Add it as a dependency in your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/junebash/swift-snapshot-testing", branch: "main"),
]
```

Then add the products you need to your test target:

```swift
targets: [
  .target(name: "MyApp"),
  .testTarget(
    name: "MyAppTests",
    dependencies: [
      "MyApp",
      .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      // Optionally, for inline snapshots:
      .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
      // Optionally, for a `customDump()` strategy powered by swift-custom-dump:
      .product(name: "SnapshotTestingCustomDump", package: "swift-snapshot-testing"),
    ]
  )
]
```

Or, in Xcode, use **File** → **Add Package Dependencies…** and enter
`https://github.com/junebash/swift-snapshot-testing`. Make sure to add the packages to a _test_
target, not your app or framework target.

## Features

  - **Dozens of snapshot strategies.** Snapshot testing isn't just for `UIView`s and `CALayer`s.
    Write snapshots against _any_ value — see the [strategy tour](#a-tour-of-the-built-in-strategies)
    above.
  - **Write your own snapshot strategies.** If you can convert it to an image, string, data, or your
    own diffable format, you can snapshot test it. Build strategies from scratch by conforming to
    `SnapshotStrategy`, or transform existing ones with `pullback`/`asyncPullback`.
  - **No configuration required.** Don't fuss with scheme settings and environment variables.
    Snapshots are automatically saved alongside your tests.
  - **More hands-off.** New snapshots are recorded whether recording is on or not.
  - **Structured concurrency, not run-loop hacks.** Assertions are `async` all the way down. There's
    no synchronous entry point that blocks a thread and spins the run loop to fake it.
  - **Device-agnostic snapshots.** Render view controllers for specific devices and trait collections
    from a single simulator.
  - **First-class Xcode support.** Image differences are captured as test attachments (via Swift
    Testing's `Attachment` API or `XCTAttachment`, depending on the test framework). Text differences
    are rendered in inline error messages.
  - **Supports any platform that supports Swift.** Write snapshot tests for iOS, Linux, macOS, and
    tvOS.
  - **SceneKit, SpriteKit, and WebKit support.** Most snapshot testing libraries don't support these
    view subclasses.
  - **`Codable` support.** Snapshot encodable data structures into their JSON and property list
    representations.
  - **Custom diff tool integration.** Configure failure messages to print diff commands for
    [Kaleidoscope](https://kaleidoscope.app) or your diff tool of choice.
    ``` swift
    await withSnapshotTesting(diffTool: .ksdiff) {
      // ...
    }
    ```

## Learn More

This library is a fork of [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing),
designed with [witness-oriented programming](https://www.pointfree.co/episodes/ep39-witness-oriented-library-design)
by [Point-Free](https://www.pointfree.co), a video series exploring functional programming and Swift
hosted by [Brandon Williams](https://twitter.com/mbrandonw) and
[Stephen Celis](https://twitter.com/stephencelis). This fork has since moved from that closure-based
witness design to protocol-based strategies with native async support, but the original library and
its design are well worth learning from:

  - [Episode 33](https://www.pointfree.co/episodes/ep33-protocol-witnesses-part-1): Protocol Witnesses: Part 1
  - [Episode 34](https://www.pointfree.co/episodes/ep34-protocol-witnesses-part-1): Protocol Witnesses: Part 2
  - [Episode 35](https://www.pointfree.co/episodes/ep35-advanced-protocol-witnesses-part-1): Advanced Protocol Witnesses: Part 1
  - [Episode 36](https://www.pointfree.co/episodes/ep36-advanced-protocol-witnesses-part-2): Advanced Protocol Witnesses: Part 2
  - [Episode 37](https://www.pointfree.co/episodes/ep37-protocol-oriented-library-design-part-1): Protocol-Oriented Library Design: Part 1
  - [Episode 38](https://www.pointfree.co/episodes/ep38-protocol-oriented-library-design-part-2): Protocol-Oriented Library Design: Part 2
  - [Episode 39](https://www.pointfree.co/episodes/ep39-witness-oriented-library-design): Witness-Oriented Library Design
  - [Episode 40](https://www.pointfree.co/episodes/ep40-async-functional-refactoring): Async Functional Refactoring
  - [Episode 41](https://www.pointfree.co/episodes/ep41-a-tour-of-snapshot-testing): A Tour of Snapshot Testing 🆓

## Related Tools

  - [`iOSSnapshotTestCase`](https://github.com/uber/ios-snapshot-test-case/) helped introduce screen
    shot testing to a broad audience in the iOS community. Experience with it inspired the creation
    of this library.

  - [Jest](https://jestjs.io) brought generalized snapshot testing to the JavaScript community with
    a polished user experience. Several features of this library (diffing, automatically capturing
    new snapshots) were directly influenced.

## License

This library, and the upstream project it's forked from, are released under the MIT license. See
[LICENSE](LICENSE) for details.
