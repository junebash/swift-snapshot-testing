#if os(iOS) || os(macOS)
  import Foundation
  import WebKit

  /// Bridges `WKWebView`'s `isLoading` KVO to a single continuation resume. Shared by the macOS
  /// (`Strategies+NSView.swift`) and iOS (`UIViewRender.swift`) render engines.
  ///
  /// KVO can fire its handler more than once and off the type system's radar, so the observation and
  /// a one-shot resume are guarded behind a lock. `@unchecked Sendable` is sound here because all
  /// access is serialized by that lock and the resume is idempotent.
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
