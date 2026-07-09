#if os(macOS) || os(iOS) || os(tvOS)
  #if os(macOS)
    import AppKit
  #else
    import UIKit
  #endif
  import CoreGraphics
  import Foundation

  // `CGPath`, `NSBezierPath`, and `UIBezierPath` are concrete value types, so like `URLRequest` in
  // `Strategies+URLRequest.swift`, these are exposed as static vars/funcs (no generic parameter
  // needed). `CGPath` is shared by all platforms; the platform bezier types pull back through it or
  // mirror it.

  extension SnapshotStrategy where Self == _Pullback<CGPath, LinesStrategy> {
    /// A snapshot strategy for comparing bezier paths based on element descriptions.
    public static var elementsDescription: _Pullback<CGPath, LinesStrategy> {
      .elementsDescription(numberFormatter: pathElementsNumberFormatter)
    }

    /// A snapshot strategy for comparing bezier paths based on element descriptions.
    ///
    /// - Parameter numberFormatter: The number formatter used for formatting points.
    public static func elementsDescription(
      numberFormatter: NumberFormatter
    ) -> _Pullback<CGPath, LinesStrategy> {
      LinesStrategy().pullback { (path: CGPath) in
        describeElements(of: path, numberFormatter: numberFormatter)
      }
    }
  }

  #if os(iOS) || os(tvOS)
    extension SnapshotStrategy where Self == _Pullback<UIBezierPath, LinesStrategy> {
      /// A snapshot strategy for comparing bezier paths based on element descriptions.
      public static var elementsDescription: _Pullback<UIBezierPath, LinesStrategy> {
        .elementsDescription(numberFormatter: pathElementsNumberFormatter)
      }

      /// A snapshot strategy for comparing bezier paths based on element descriptions.
      ///
      /// The description is taken from the path's `cgPath` inside a single transform (rather than
      /// pulling back through the `CGPath` strategy) so only a `Sendable` `String` ever crosses the
      /// `sending` boundary — `path.cgPath` may alias its bezier path, so it can't itself be sent.
      ///
      /// - Parameter numberFormatter: The number formatter used for formatting points.
      public static func elementsDescription(
        numberFormatter: NumberFormatter
      ) -> _Pullback<UIBezierPath, LinesStrategy> {
        LinesStrategy().pullback { (path: UIBezierPath) in
          describeElements(of: path.cgPath, numberFormatter: numberFormatter)
        }
      }
    }
  #endif

  /// The element-by-element description shared by the `CGPath` and `UIBezierPath`
  /// `.elementsDescription` strategies (the `NSBezierPath` variant walks AppKit's own element API
  /// instead, matching the legacy output for its distinct element set).
  private func describeElements(of path: CGPath, numberFormatter: NumberFormatter) -> String {
    let namesByType: [CGPathElementType: String] = [
      .moveToPoint: "MoveTo",
      .addLineToPoint: "LineTo",
      .addQuadCurveToPoint: "QuadCurveTo",
      .addCurveToPoint: "CurveTo",
      .closeSubpath: "Close",
    ]

    let numberOfPointsByType: [CGPathElementType: Int] = [
      .moveToPoint: 1,
      .addLineToPoint: 1,
      .addQuadCurveToPoint: 2,
      .addCurveToPoint: 3,
      .closeSubpath: 0,
    ]

    var string: String = ""

    path.applyWithBlock { elementPointer in
      let element = elementPointer.pointee
      let name = namesByType[element.type] ?? "Unknown"

      if element.type == .moveToPoint && !string.isEmpty {
        string += "\n"
      }

      string += name

      if let numberOfPoints = numberOfPointsByType[element.type] {
        let points = UnsafeBufferPointer(start: element.points, count: numberOfPoints)
        string +=
          " "
          + points.map { point in
            let x = numberFormatter.string(from: point.x as NSNumber) ?? ""
            let y = numberFormatter.string(from: point.y as NSNumber) ?? ""
            return "(\(x), \(y))"
          }.joined(separator: " ")
      }

      string += "\n"
    }

    return string
  }

  #if os(macOS)
  extension SnapshotStrategy where Self == _Pullback<NSBezierPath, LinesStrategy> {
    /// A snapshot strategy for comparing bezier paths based on element descriptions.
    public static var elementsDescription: _Pullback<NSBezierPath, LinesStrategy> {
      .elementsDescription(numberFormatter: pathElementsNumberFormatter)
    }

    /// A snapshot strategy for comparing bezier paths based on element descriptions.
    ///
    /// - Parameter numberFormatter: The number formatter used for formatting points.
    public static func elementsDescription(
      numberFormatter: NumberFormatter
    ) -> _Pullback<NSBezierPath, LinesStrategy> {
      let namesByType: [NSBezierPath.ElementType: String] = [
        .moveTo: "MoveTo",
        .lineTo: "LineTo",
        .curveTo: "CurveTo",
        .closePath: "Close",
      ]

      let numberOfPointsByType: [NSBezierPath.ElementType: Int] = [
        .moveTo: 1,
        .lineTo: 1,
        .curveTo: 3,
        .closePath: 0,
      ]

      return LinesStrategy().pullback { (path: NSBezierPath) in
        var string: String = ""

        var elementPoints = [CGPoint](repeating: .zero, count: 3)
        for elementIndex in 0..<path.elementCount {
          let elementType = path.element(at: elementIndex, associatedPoints: &elementPoints)
          let name = namesByType[elementType] ?? "Unknown"

          if elementType == .moveTo && !string.isEmpty {
            string += "\n"
          }

          string += name

          if let numberOfPoints = numberOfPointsByType[elementType] {
            let points = elementPoints[0..<numberOfPoints]
            string +=
              " "
              + points.map { point in
                let x = numberFormatter.string(from: point.x as NSNumber) ?? ""
                let y = numberFormatter.string(from: point.y as NSNumber) ?? ""
                return "(\(x), \(y))"
              }.joined(separator: " ")
          }

          string += "\n"
        }

        return string
      }
    }
  }
  #endif

  /// Shared by the `.elementsDescription` strategies above.
  private let pathElementsNumberFormatter: NumberFormatter = {
    let numberFormatter = NumberFormatter()
    numberFormatter.decimalSeparator = "."
    numberFormatter.minimumFractionDigits = 1
    numberFormatter.maximumFractionDigits = 3
    return numberFormatter
  }()
#endif
