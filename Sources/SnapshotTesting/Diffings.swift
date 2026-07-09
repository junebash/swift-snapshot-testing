import Foundation

/// Line-diffing for UTF-8 text. The protocol form of the old `Diffing<String>.lines`.
public struct LinesDiffing: DiffStrategy {
  public typealias Value = String

  public init() {}

  public func data(from value: String) -> Data {
    Data(value.utf8)
  }

  public func value(from data: Data) throws -> String {
    String(decoding: data, as: UTF8.self)
  }

  public func diff(_ reference: String, _ candidate: String) -> SnapshotDifference? {
    guard reference != candidate else { return nil }
    let hunks = chunk(
      diff: SnapshotTesting.diff(
        reference.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
        candidate.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      ))
    let failure =
      hunks
      .flatMap { [$0.patchMark] + $0.lines }
      .joined(separator: "\n")
    let attachment = SnapshotAttachment(name: "difference.patch", data: Data(failure.utf8))
    return SnapshotDifference(message: failure, attachments: [attachment])
  }
}

/// Byte-for-byte data diffing. The protocol form of the old `Diffing<Data>` in `Data.swift`.
public struct DataDiffing: DiffStrategy {
  public typealias Value = Data

  public init() {}

  public func data(from value: Data) -> Data { value }

  public func value(from data: Data) throws -> Data { data }

  public func diff(_ reference: Data, _ candidate: Data) -> SnapshotDifference? {
    guard reference != candidate else { return nil }
    return SnapshotDifference(
      message: "Expected \(candidate) to match \(reference)",
      attachments: []
    )
  }
}
