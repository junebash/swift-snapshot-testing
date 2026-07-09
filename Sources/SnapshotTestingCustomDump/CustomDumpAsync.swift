import CustomDump
import SnapshotTestingAsync

extension SnapshotStrategy {
  /// A snapshot strategy for comparing any structure based on a
  /// [custom dump](https://github.com/pointfreeco/swift-custom-dump).
  ///
  /// ```swift
  /// await assertSnapshot(of: user, as: .customDump())
  /// ```
  ///
  /// Records:
  ///
  /// ```
  /// User(
  ///   bio: "Blobbed around the world.",
  ///   id: 1,
  ///   name: "Blobby"
  /// )
  /// ```
  public static func customDump<Value>() -> _Pullback<Value, LinesStrategy>
  where Self == _Pullback<Value, LinesStrategy> {
    LinesStrategy().pullback { (value: Value) in String(customDumping: value) }
  }
}
