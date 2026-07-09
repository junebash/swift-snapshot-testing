import Foundation

/// Compares strings by line-diffing. The protocol form of `Snapshotting<String, String>.lines`.
public struct LinesStrategy: SnapshotStrategy {
  public typealias Value = String
  public typealias Format = String

  public init() {}

  public var pathExtension: String? { "txt" }
  public var diffing: LinesDiffing { LinesDiffing() }

  // A value strategy: a plain, non-main-actor synchronous witness. It satisfies the
  // `nonisolated(nonsending)` async requirement (sync is weaker than async) and echoes `sending`.
  public func snapshot(of value: sending String) -> sending String { value }
}

extension SnapshotStrategy where Self == LinesStrategy {
  /// A snapshot strategy for comparing strings based on equality.
  public static var lines: LinesStrategy { LinesStrategy() }
}

/// Compares raw data by byte equality. The protocol form of `Snapshotting<Data, Data>.data`.
public struct RawDataStrategy: SnapshotStrategy {
  public typealias Value = Data
  public typealias Format = Data

  public init() {}

  public var pathExtension: String? { nil }
  public var diffing: DataDiffing { DataDiffing() }

  public func snapshot(of value: sending Data) -> sending Data { value }
}

extension SnapshotStrategy where Self == RawDataStrategy {
  /// A snapshot strategy for comparing data based on byte equality.
  public static var data: RawDataStrategy { RawDataStrategy() }
}
