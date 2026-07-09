#if os(iOS)
  import SwiftUI
  import Testing
  import UIKit

  @testable import SnapshotTesting

  /// Coverage for the UIKit view-family strategies (`UIView`/`UIViewController`/SwiftUI `.image`,
  /// `.recursiveDescription`, `.hierarchy`).
  ///
  /// These are determinism/behavior tests, not byte-identity tests: the legacy `testUIView`
  /// references were recorded on iOS 13 from a `contactAdd` `UIButton`, whose glyph rendering and
  /// UIKit's `recursiveDescription` format have both drifted across major iOS versions. The pixel
  /// pipeline itself (render → sRGB remap → PNG) is already validated byte-for-byte against a
  /// legacy reference by `IOSCanaryTests.caLayerImageMatchesLegacyReferenceByteForByte`.
  @Suite @MainActor struct UIViewStrategyTests {
    private func makeRedView() -> UIView {
      let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
      view.backgroundColor = .red
      return view
    }

    @Test func viewImageRendersDeterministically() async throws {
      let reference = await _recordSnapshot(of: makeRedView(), as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(of: makeRedView(), as: .image, reference: reference)
      #expect(rerendered == nil)
    }

    @Test func viewImageDetectsRealDifference() async throws {
      let reference = await _recordSnapshot(of: makeRedView(), as: .image)
      let blueView = makeRedView()
      blueView.backgroundColor = .blue
      let diff = try await _verifySnapshot(of: blueView, as: .image, reference: reference)
      #expect(diff != nil)
    }

    @Test func viewImageHonorsSizeOverride() async throws {
      let strategy = UIViewImageStrategy(size: CGSize(width: 20, height: 20))
      let image = await strategy.snapshot(of: makeRedView())
      #expect(image.size == CGSize(width: 20, height: 20))
    }

    @Test func viewRecursiveDescriptionIsDeterministicAndDescribesTheView() async throws {
      let reference = await _recordSnapshot(of: makeRedView(), as: .recursiveDescription)
      let text = String(decoding: reference, as: UTF8.self)
      #expect(text.contains("UIView"))
      #expect(text.contains("(0 0; 10 10)"))
      let diff = try await _verifySnapshot(
        of: makeRedView(), as: .recursiveDescription, reference: reference)
      #expect(diff == nil)
    }

    @Test func viewControllerImageRendersDeterministically() async throws {
      func makeController() -> UIViewController {
        let controller = UIViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        controller.view.backgroundColor = .green
        return controller
      }
      let reference = await _recordSnapshot(of: makeController(), as: .image)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: makeController(), as: .image, reference: reference)
      #expect(rerendered == nil)
    }

    @Test func viewControllerHierarchyDescribesEmbeddedControllers() async throws {
      let tab = UITabBarController()
      tab.viewControllers = [UINavigationController(rootViewController: UIViewController())]
      let reference = await _recordSnapshot(of: tab, as: .hierarchy)
      let text = String(decoding: reference, as: UTF8.self)
      #expect(text.contains("UITabBarController"))
      #expect(text.contains("UINavigationController"))
    }

    @Test func swiftUIViewImageRendersDeterministically() async throws {
      struct FixtureView: View {
        var body: some View {
          Rectangle().fill(Color.red).frame(width: 10, height: 10)
        }
      }
      let strategy = SwiftUIViewImageStrategy<FixtureView>(layout: .fixed(width: 20, height: 20))
      let reference = await _recordSnapshot(of: FixtureView(), as: strategy)
      #expect(!reference.isEmpty)
      let rerendered = try await _verifySnapshot(
        of: FixtureView(), as: strategy, reference: reference)
      #expect(rerendered == nil)
    }
  }
#endif
