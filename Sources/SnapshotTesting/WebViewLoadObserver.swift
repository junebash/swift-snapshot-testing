#if os(iOS) || os(macOS)
  import Foundation
  import WebKit

  /// Bridges `WKWebView`'s `isLoading` KVO to a single continuation resume. Shared by the macOS
  /// (`Strategies+NSView.swift`) and iOS (`UIViewRender.swift`) render engines.
  ///
  /// KVO can fire its handler more than once and off the type system's radar, so the observation and
  /// a one-shot resume are guarded behind a lock. `@unchecked Sendable` is sound here because all
  /// access is serialized by that lock and the resume is idempotent.
  /// Bridges a main-actor callback API to `async`, bounded by the ambient snapshot timeout.
  ///
  /// The `start` closure receives a one-shot `finish` callback. If the ambient
  /// ``SnapshotCaptureContext`` timeout elapses before `finish` is called, the context is flagged
  /// as timed out and `nil` is returned; a later `finish` is ignored. This is how the assertion's
  /// `timeout` parameter reaches the only places a capture can actually stall — the engines'
  /// genuine suspension points — without giving up the eager synchronous prefix.
  @MainActor
  func awaitCallback<T>(
    _ start: (_ finish: @escaping (sending T?) -> Void) -> Void
  ) async -> T? {
    let context = SnapshotCaptureContext.current
    return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
      let oneShot = OneShotResume(continuation)
      if let context {
        DispatchQueue.global().asyncAfter(deadline: .now() + context.timeout) {
          if oneShot.resumeIfFirst(with: nil) {
            context.markTimedOut()
          }
        }
      }
      start { value in
        _ = oneShot.resumeIfFirst(with: value)
      }
    }
  }

  /// Guards a continuation so that racing resumers (the capture callback vs. the timeout timer)
  /// resolve to exactly one resume. `@unchecked Sendable` is sound: all access is serialized by
  /// the lock, and the only value that crosses off the main actor is the timer's `nil`.
  private final class OneShotResume<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
      self.continuation = continuation
    }

    /// Resumes the continuation if nothing has yet; returns whether this call won the race.
    func resumeIfFirst(with value: sending T?) -> Bool {
      lock.lock()
      let continuation = self.continuation
      self.continuation = nil
      lock.unlock()
      guard let continuation else { return false }
      continuation.resume(returning: value)
      return true
    }
  }

  final class WebViewLoadObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?
    private var resume: (() -> Void)?

    @MainActor
    init(_ webView: WKWebView, resume: @escaping () -> Void) {
      self.resume = resume
      self.observation = webView.observe(\.isLoading, options: [.initial, .new]) {
        [weak self] _, change in
        guard change.newValue == false else { return }
        self?.finish()
      }
    }

    private func finish() {
      lock.lock()
      let resume = self.resume
      self.resume = nil
      self.observation?.invalidate()
      self.observation = nil
      lock.unlock()
      resume?()
    }
  }
#endif
