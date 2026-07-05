import Foundation

/// A wrapper around an asynchronous operation.
///
/// Snapshot strategies may utilize this type to create snapshots in an asynchronous fashion.
///
/// For example, WebKit's `WKWebView` offers a callback-based API for taking image snapshots
/// (`takeSnapshot`). `Async` allows us to build a value that can pass its callback along to the
/// scope in which the image has been created.
///
/// ```swift
/// Async<UIImage> { callback in
///   webView.takeSnapshot(with: nil) { image, error in
///     callback(image!)
///   }
/// }
/// ```
public struct Async<Value> {
  public let run: (@escaping (Value) -> Void) -> Void

  /// Creates an asynchronous operation.
  ///
  /// - Parameters:
  ///   - run: A function that, when called, can hand a value to a callback.
  public init(run: @escaping (_ callback: @escaping (Value) -> Void) -> Void) {
    self.run = run
  }

  /// Wraps a pure value in an asynchronous operation.
  ///
  /// - Parameter value: A value to be wrapped in an asynchronous operation.
  public init(value: Value) {
    self.init { callback in callback(value) }
  }

  /// Creates an asynchronous operation from an `async` function.
  ///
  /// Use this initializer to define a snapshot strategy with modern Swift concurrency:
  ///
  /// ```swift
  /// Async {
  ///   await webView.takeSnapshot()
  /// }
  /// ```
  ///
  /// - Parameter operation: An asynchronous operation that produces a value.
  public init(operation: @escaping () async -> Value) {
    self.init { callback in
      Task {
        callback(await operation())
      }
    }
  }

  /// Transforms an `Async<Value>` into an `Async<NewValue>` with a function `(Value) -> NewValue`.
  ///
  /// - Parameter transform: A transformation to apply to the value wrapped by the async value.
  public func map<NewValue>(_ transform: @escaping (Value) -> NewValue) -> Async<NewValue> {
    .init { callback in
      self.run { value in callback(transform(value)) }
    }
  }

  /// The value produced by this asynchronous operation.
  ///
  /// Awaiting this property suspends the current task without blocking the current thread, which
  /// makes it a modern concurrency-friendly alternative to waiting on ``run`` with an
  /// `XCTestExpectation`. If the underlying operation invokes its callback more than once, all
  /// values after the first are ignored.
  public var value: Value {
    get async {
      let onceGuard = OnceGuard()
      return await withCheckedContinuation { continuation in
        self.run { value in
          guard onceGuard.claim() else { return }
          continuation.resume(returning: value)
        }
      }
    }
  }
}

/// A thread-safe guard that allows exactly one claimant, used to protect continuations from
/// callback-based operations that may call back more than once (or race with a timeout).
final class OnceGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var isClaimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !isClaimed else { return false }
    isClaimed = true
    return true
  }
}
