import Foundation

// Encodable value strategies that pull back to `LinesStrategy`. Mirrors the fan-out pattern in
// `Strategies+Any.swift`: a generic strategy is exposed as a static function on a `Self ==`
// constrained extension (a generic static var isn't possible), returning the concrete pullback
// type with its path extension applied.

extension SnapshotStrategy {
  /// A snapshot strategy for comparing encodable structures based on their JSON representation.
  ///
  /// ```swift
  /// assertSnapshot(of: user, as: .json())
  /// ```
  ///
  /// Records:
  ///
  /// ```json
  /// {
  ///   "bio" : "Blobbed around the world.",
  ///   "id" : 1,
  ///   "name" : "Blobby"
  /// }
  /// ```
  public static func json<Value: Encodable>() -> _PathExtension<_Pullback<Value, LinesStrategy>>
  where Self == _PathExtension<_Pullback<Value, LinesStrategy>> {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return .json(encoder)
  }

  /// A snapshot strategy for comparing encodable structures based on their JSON representation.
  ///
  /// - Parameter encoder: A JSON encoder.
  public static func json<Value: Encodable>(
    _ encoder: JSONEncoder
  ) -> _PathExtension<_Pullback<Value, LinesStrategy>>
  where Self == _PathExtension<_Pullback<Value, LinesStrategy>> {
    LinesStrategy().pullback { (value: Value) -> String in
      do {
        return try String(decoding: encoder.encode(value), as: UTF8.self)
      } catch {
        fatalError("Could not encode value as JSON: \(error)")
      }
    }
    .pathExtension("json")
  }

  /// A snapshot strategy for comparing encodable structures based on their property list
  /// representation.
  ///
  /// ```swift
  /// assertSnapshot(of: user, as: .plist())
  /// ```
  ///
  /// Records:
  ///
  /// ```xml
  /// <?xml version="1.0" encoding="UTF-8"?>
  /// <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  ///  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  /// <plist version="1.0">
  /// <dict>
  ///   <key>bio</key>
  ///   <string>Blobbed around the world.</string>
  ///   <key>id</key>
  ///   <integer>1</integer>
  ///   <key>name</key>
  ///   <string>Blobby</string>
  /// </dict>
  /// </plist>
  /// ```
  public static func plist<Value: Encodable>() -> _PathExtension<_Pullback<Value, LinesStrategy>>
  where Self == _PathExtension<_Pullback<Value, LinesStrategy>> {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    return .plist(encoder)
  }

  /// A snapshot strategy for comparing encodable structures based on their property list
  /// representation.
  ///
  /// - Parameter encoder: A property list encoder.
  public static func plist<Value: Encodable>(
    _ encoder: PropertyListEncoder
  ) -> _PathExtension<_Pullback<Value, LinesStrategy>>
  where Self == _PathExtension<_Pullback<Value, LinesStrategy>> {
    LinesStrategy().pullback { (value: Value) -> String in
      do {
        return try String(decoding: encoder.encode(value), as: UTF8.self)
      } catch {
        fatalError("Could not encode value as a property list: \(error)")
      }
    }
    .pathExtension("plist")
  }
}
