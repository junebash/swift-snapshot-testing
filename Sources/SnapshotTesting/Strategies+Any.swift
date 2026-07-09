import Foundation

// Value strategies that pull back to `LinesStrategy`. These are the template for the mechanical
// value-strategy fan-out: a generic strategy is exposed as a static *function* on a `Self ==`
// constrained extension (a generic static *var* isn't possible), returning the concrete pullback
// type. The transform is `@MainActor` (harmless for pure value work) and echoes `sending`.

extension SnapshotStrategy {
  /// A snapshot strategy that captures a value's textual description via `String(describing:)`.
  ///
  /// ```swift
  /// assertSnapshot(of: user, as: .description())
  /// ```
  public static func description<Value>() -> _Pullback<Value, LinesStrategy>
  where Self == _Pullback<Value, LinesStrategy> {
    LinesStrategy().pullback { (value: Value) in String(describing: value) }
  }

  /// A snapshot strategy for comparing any structure based on a sanitized text dump.
  ///
  /// Mirrors Swift's `dump`, but strips pointer addresses and sorts non-deterministic collections
  /// (dictionaries, sets) so output is stable.
  ///
  /// ```swift
  /// assertSnapshot(of: user, as: .dump())
  /// ```
  public static func dump<Value>() -> _Pullback<Value, LinesStrategy>
  where Self == _Pullback<Value, LinesStrategy> {
    LinesStrategy().pullback { (value: Value) in snap(value) }
  }

  /// A snapshot strategy for comparing any structure based on its pretty-printed JSON representation.
  public static func json<Value>() -> _PathExtension<_Pullback<Value, LinesStrategy>>
  where Self == _PathExtension<_Pullback<Value, LinesStrategy>> {
    let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
    return LinesStrategy().pullback { (value: Value) -> String in
      do {
        let data = try JSONSerialization.data(withJSONObject: value, options: options)
        return String(decoding: data, as: UTF8.self)
      } catch {
        fatalError("Could not serialize value to JSON: \(error)")
      }
    }
    .pathExtension("json")
  }
}

private func snap<T>(
  _ value: T,
  name: String? = nil,
  indent: Int = 0,
  visitedValues: Set<ObjectIdentifier> = .init()
) -> String {
  let indentation = String(repeating: " ", count: indent)
  let mirror = Mirror(reflecting: value)
  var children = mirror.children
  let count = children.count
  let bullet = count == 0 ? "-" : "▿"
  var visitedValues = visitedValues

  let description: String
  switch (value, mirror.displayStyle) {
  case (_, .collection?):
    description = count == 1 ? "1 element" : "\(count) elements"
  case (_, .dictionary?):
    description = count == 1 ? "1 key/value pair" : "\(count) key/value pairs"
    children = sort(children, visitedValues: visitedValues)
  case (_, .set?):
    description = count == 1 ? "1 member" : "\(count) members"
    children = sort(children, visitedValues: visitedValues)
  case (_, .tuple?):
    description = count == 1 ? "(1 element)" : "(\(count) elements)"
  case (_, .optional?):
    let subjectType = String(describing: mirror.subjectType)
      .replacingOccurrences(of: " #\\d+", with: "", options: .regularExpression)
    description = count == 0 ? "\(subjectType).none" : "\(subjectType)"
  case (let value as AnySnapshotStringConvertible, _) where type(of: value).renderChildren:
    description = value.snapshotDescription
  case (let value as AnySnapshotStringConvertible, _):
    return "\(indentation)- \(name.map { "\($0): " } ?? "")\(value.snapshotDescription)\n"
  case (let value as CustomStringConvertible, _):
    description = value.description
  case let (value as AnyObject, .class?):
    let objectID = ObjectIdentifier(value)
    if visitedValues.contains(objectID) {
      return "\(indentation)\(bullet) \(name ?? "value") (circular reference detected)\n"
    }
    visitedValues.insert(objectID)
    description = String(describing: mirror.subjectType)
      .replacingOccurrences(of: " #\\d+", with: "", options: .regularExpression)
    children = sort(children, visitedValues: visitedValues)
  case (_, .struct?):
    description = String(describing: mirror.subjectType)
      .replacingOccurrences(of: " #\\d+", with: "", options: .regularExpression)
    children = sort(children, visitedValues: visitedValues)
  case (_, .enum?):
    let subjectType = String(describing: mirror.subjectType)
      .replacingOccurrences(of: " #\\d+", with: "", options: .regularExpression)
    description = count == 0 ? "\(subjectType).\(value)" : "\(subjectType)"
  case (let value, _):
    description = String(describing: value)
  }

  let lines =
    ["\(indentation)\(bullet) \(name.map { "\($0): " } ?? "")\(description)\n"]
    + children.map { snap($1, name: $0, indent: indent + 2, visitedValues: visitedValues) }

  return lines.joined()
}

private func sort(_ children: Mirror.Children, visitedValues: Set<ObjectIdentifier>)
  -> Mirror.Children
{
  return .init(
    children
      .map({ (child: $0, snap: snap($0, visitedValues: visitedValues)) })
      .sorted(by: { $0.snap < $1.snap })
      .map({ $0.child })
  )
}

/// A type with a customized snapshot dump representation.
public protocol AnySnapshotStringConvertible {
  /// Whether or not to dump child nodes (defaults to `false`).
  static var renderChildren: Bool { get }

  /// A textual snapshot dump representation of this instance.
  var snapshotDescription: String { get }
}

extension AnySnapshotStringConvertible {
  public static var renderChildren: Bool { false }
}

extension Character: AnySnapshotStringConvertible {
  public var snapshotDescription: String { debugDescription }
}

extension Data: AnySnapshotStringConvertible {
  public var snapshotDescription: String { debugDescription }
}

extension Date: AnySnapshotStringConvertible {
  public var snapshotDescription: String { snapshotDateFormatter.string(from: self) }
}

extension NSObject: AnySnapshotStringConvertible {
  #if canImport(ObjectiveC)
    @objc open var snapshotDescription: String { purgePointers(self.debugDescription) }
  #else
    open var snapshotDescription: String { purgePointers(self.debugDescription) }
  #endif
}

extension String: AnySnapshotStringConvertible {
  public var snapshotDescription: String { debugDescription }
}

extension Substring: AnySnapshotStringConvertible {
  public var snapshotDescription: String { debugDescription }
}

extension URL: AnySnapshotStringConvertible {
  public var snapshotDescription: String { debugDescription }
}

private let snapshotDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(abbreviation: "UTC")
  return formatter
}()

/// Strips pointer addresses from a description so snapshots are deterministic.
func purgePointers(_ string: String) -> String {
  string.replacingOccurrences(
    of: ":?\\s*0x[\\da-f]+(\\s*)", with: "$1", options: .regularExpression)
}
