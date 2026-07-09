/// A strategy for turning a value into a diffable format for snapshot testing.
///
/// This is the protocol form of the old `Snapshotting<Value, Format>` witness struct. A conforming
/// type knows how to render a `Value` (a view, a request, a model) into a `Format` (an image, a
/// string, raw data) that a ``DiffStrategy`` can serialize and compare.
///
/// ## Isolation
///
/// The core requirement is `nonisolated(nonsending)`, meaning ``snapshot(of:)`` runs on the
/// *caller's* executor rather than hopping to a fixed one. This is what gives **eager capture**:
/// when the assertion caller is on `@MainActor`, a synchronous view-rendering witness runs its
/// capture in the caller's run-loop turn — before any queued `main.async`/CoreAnimation work can
/// mutate the subject — with no thread hop.
///
/// - Value strategies (`String`, `Data`, `Encodable`, …) conform with plain `nonisolated`
///   synchronous witnesses; they are not pinned to the main actor.
/// - View / image strategies conform with `@MainActor` witnesses; the `sending` parameter is what
///   lets a non-`Sendable` `Value` (e.g. `NSView`) cross into the main-actor witness, and the
///   `sending` result is what lets a non-`Sendable` `Format` (e.g. `NSImage`) cross back out.
public protocol SnapshotStrategy<Value, Format> {
  /// The type this strategy snapshots (e.g. `UIView`, `URLRequest`).
  associatedtype Value

  /// The diffable format captures reduce to (e.g. `UIImage`, `String`, `Data`).
  associatedtype Format

  /// The strategy used to serialize and compare the captured ``Format``.
  associatedtype Diffing: DiffStrategy where Diffing.Value == Format

  /// The path extension applied to reference files saved to disk (e.g. `"png"`, `"txt"`), or `nil`.
  var pathExtension: String? { get }

  /// The diffing strategy for the captured format.
  var diffing: Diffing { get }

  /// Captures `value` as a diffable ``Format``.
  ///
  /// Runs on the caller's executor (see the type-level isolation note). `value` is `sending`: the
  /// caller transfers ownership into the strategy, which allows a non-`Sendable` value to cross
  /// into a `@MainActor` witness. The result is likewise `sending` so a non-`Sendable` format can
  /// flow back to the caller.
  nonisolated(nonsending) func snapshot(of value: sending Value) async -> sending Format
}

// MARK: - Pullback

extension SnapshotStrategy {
  /// Derives a strategy for a new value type by transforming it into this strategy's value type.
  ///
  /// The transform is `@MainActor` so it may touch main-actor-isolated state (e.g. reading a
  /// controller's `view`); on a `@MainActor` caller it runs eagerly with no hop. For a pure value
  /// transform this is harmless — the closure simply runs on the main actor.
  public func pullback<New>(
    _ transform: @escaping @MainActor (sending New) -> sending Value
  ) -> _Pullback<New, Self> {
    _Pullback(base: self, transform: transform)
  }

  /// Like ``pullback(_:)`` but for a transform that must itself `await` (e.g. rendering a view that
  /// suspends on a web/scene subview before the base strategy can run).
  public func asyncPullback<New>(
    _ transform: @escaping @MainActor (sending New) async -> sending Value
  ) -> _AsyncPullback<New, Self> {
    _AsyncPullback(base: self, transform: transform)
  }
}

/// The strategy produced by ``SnapshotStrategy/pullback(_:)``. Public so `some SnapshotStrategy`
/// return types resolve; not intended to be named directly.
public struct _Pullback<New, Base: SnapshotStrategy>: SnapshotStrategy {
  public typealias Value = New
  public typealias Format = Base.Format
  public typealias Diffing = Base.Diffing

  let base: Base
  let transform: @MainActor (sending New) -> sending Base.Value

  public var pathExtension: String? { base.pathExtension }
  public var diffing: Base.Diffing { base.diffing }

  public nonisolated(nonsending) func snapshot(of value: sending New) async -> sending Base.Format {
    let transformed = await transform(value)
    return await base.snapshot(of: transformed)
  }
}

extension SnapshotStrategy {
  /// Overrides the path extension used for reference files (e.g. `"json"`), leaving capture and
  /// diffing unchanged. Replaces the old mutable `Snapshotting.pathExtension` assignment.
  public func pathExtension(_ pathExtension: String?) -> _PathExtension<Self> {
    _PathExtension(base: self, pathExtension: pathExtension)
  }
}

/// The strategy produced by ``SnapshotStrategy/pathExtension(_:)``. Public so `some SnapshotStrategy`
/// return types resolve; not intended to be named directly.
public struct _PathExtension<Base: SnapshotStrategy>: SnapshotStrategy {
  public typealias Value = Base.Value
  public typealias Format = Base.Format
  public typealias Diffing = Base.Diffing

  let base: Base
  public let pathExtension: String?

  public var diffing: Base.Diffing { base.diffing }

  public nonisolated(nonsending) func snapshot(of value: sending Base.Value) async -> sending Base
    .Format
  {
    await base.snapshot(of: value)
  }
}

/// The strategy produced by ``SnapshotStrategy/asyncPullback(_:)``. Public so `some SnapshotStrategy`
/// return types resolve; not intended to be named directly.
public struct _AsyncPullback<New, Base: SnapshotStrategy>: SnapshotStrategy {
  public typealias Value = New
  public typealias Format = Base.Format
  public typealias Diffing = Base.Diffing

  let base: Base
  let transform: @MainActor (sending New) async -> sending Base.Value

  public var pathExtension: String? { base.pathExtension }
  public var diffing: Base.Diffing { base.diffing }

  public nonisolated(nonsending) func snapshot(of value: sending New) async -> sending Base.Format {
    let transformed = await transform(value)
    return await base.snapshot(of: transformed)
  }
}
