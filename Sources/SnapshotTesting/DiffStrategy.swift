import Foundation

/// An artifact produced by a failing diff — a reference image, a failure image, a textual patch —
/// that the assertion layer surfaces to the test framework (Swift Testing / XCTest attachments).
///
/// This replaces the old `DiffAttachment` enum. There is no `XCTAttachment` case: attachments are
/// carried as raw bytes plus enough metadata for either framework to render them, so the diffing
/// layer no longer depends on XCTest.
public struct SnapshotAttachment: Sendable {
  /// A human-readable name (e.g. `"reference"`, `"failure"`, `"difference"`).
  public var name: String?

  /// The attachment's raw bytes.
  public var data: Data

  /// A Uniform Type Identifier describing `data` (e.g. `"public.png"`), when known.
  public var uniformTypeIdentifier: String?

  public init(name: String? = nil, data: Data, uniformTypeIdentifier: String? = nil) {
    self.name = name
    self.data = data
    self.uniformTypeIdentifier = uniformTypeIdentifier
  }
}

/// The result of a failed comparison: a message describing the difference plus any attachments
/// that help a human see it.
public struct SnapshotDifference: Sendable {
  public var message: String
  public var attachments: [SnapshotAttachment]

  public init(message: String, attachments: [SnapshotAttachment] = []) {
    self.message = message
    self.attachments = attachments
  }
}

/// A strategy for serializing a diffable format to/from disk and comparing two instances of it.
///
/// This is the protocol form of the old `Diffing<Value>` witness struct. Conforming types are the
/// leaves of the snapshot system: `String` line diffing, `Data` byte diffing, and the platform
/// image diffings. The serialization and comparison are intentionally **synchronous** — they never
/// touch the main actor or await — so they compose freely underneath the async `SnapshotStrategy`.
public protocol DiffStrategy<Value>: Sendable {
  associatedtype Value

  /// Serializes a value to the bytes written to (and read back from) a reference file on disk.
  func data(from value: Value) -> Data

  /// Reconstructs a value from bytes previously produced by ``data(from:)``.
  func value(from data: Data) throws -> Value

  /// Compares a reference value against a freshly captured one.
  ///
  /// Returns `nil` when they match. Otherwise returns a ``SnapshotDifference`` describing the
  /// mismatch and any attachments (reference/failure/difference artifacts) worth surfacing.
  func diff(_ reference: Value, _ candidate: Value) -> SnapshotDifference?
}
