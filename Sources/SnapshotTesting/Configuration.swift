import Foundation

#if canImport(Testing)
  import Testing
#endif

// The task-local configuration layer, ported from the legacy `SnapshotTestingConfiguration.swift`
// and `SnapshotsTestTrait.swift`. Engine-agnostic; survives the flip unchanged. The legacy mutable
// globals (`isRecording`, `diffTool`, `__record`) are deliberately not ported — configuration
// flows only through the environment, the `.snapshots` test trait, `withSnapshotTesting`, and
// per-assertion parameters.

/// Customizes `assertSnapshot` for the duration of an operation.
///
/// Use this operation to customize how the `assertSnapshot` function behaves in a test. It is
/// most convenient to use in the context of Swift Testing's `.snapshots` trait, but it can also
/// be used directly to wrap a scope.
public func withSnapshotTesting<R>(
  record: SnapshotTestingConfiguration.Record? = nil,
  diffTool: SnapshotTestingConfiguration.DiffTool? = nil,
  operation: () throws -> R
) rethrows -> R {
  try SnapshotTestingConfiguration.$current.withValue(
    SnapshotTestingConfiguration(
      record: record ?? SnapshotTestingConfiguration.current?.record ?? defaultRecordMode,
      diffTool: diffTool ?? SnapshotTestingConfiguration.current?.diffTool ?? defaultDiffTool
    )
  ) {
    try operation()
  }
}

/// Customizes `assertSnapshot` for the duration of an asynchronous operation.
public func withSnapshotTesting<R>(
  record: SnapshotTestingConfiguration.Record? = nil,
  diffTool: SnapshotTestingConfiguration.DiffTool? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws -> R
) async rethrows -> R {
  try await SnapshotTestingConfiguration.$current.withValue(
    SnapshotTestingConfiguration(
      record: record ?? SnapshotTestingConfiguration.current?.record ?? defaultRecordMode,
      diffTool: diffTool ?? SnapshotTestingConfiguration.current?.diffTool ?? defaultDiffTool
    ),
    operation: operation,
    isolation: isolation
  )
}

/// The configuration for a snapshot test.
public struct SnapshotTestingConfiguration: Sendable {
  @TaskLocal public static var current: Self?

  /// The diff tool used to print helpful test failure messages.
  public var diffTool: DiffTool?

  /// The recording strategy to use while running snapshot tests.
  public var record: Record?

  public init(
    record: Record?,
    diffTool: DiffTool?
  ) {
    self.diffTool = diffTool
    self.record = record
  }

  /// The record mode of the snapshot test.
  public struct Record: Equatable, Sendable {
    private let storage: Storage

    public init?(rawValue: String) {
      switch rawValue {
      case "all":
        self.storage = .all
      case "failed":
        self.storage = .failed
      case "missing":
        self.storage = .missing
      case "never":
        self.storage = .never
      default:
        return nil
      }
    }

    /// Records all snapshots to disk, no matter what.
    public static let all = Self(storage: .all)

    /// Records snapshots for assertions that fail. This can be useful for tests that use precision
    /// thresholds so that passing tests do not re-record snapshots that are subtly different but
    /// still within the threshold.
    public static let failed = Self(storage: .failed)

    /// Records only the snapshots that are missing from disk.
    public static let missing = Self(storage: .missing)

    /// Does not record any snapshots. If a snapshot is missing a test failure will be raised. This
    /// option is appropriate when running tests on CI so that re-tries of tests do not
    /// surprisingly pass after snapshots are unexpectedly generated.
    public static let never = Self(storage: .never)

    private init(storage: Storage) {
      self.storage = storage
    }

    private enum Storage: Equatable, Sendable {
      case all
      case failed
      case missing
      case never
    }
  }

  /// Describes the diff command used to diff two files on disk.
  ///
  /// This type can be created with a closure that takes two arguments: the first argument is
  /// a file path to the currently recorded snapshot on disk, and the second argument is the
  /// file path to a _failed_ snapshot that was recorded to a temporary location on disk. You can
  /// use these two file paths to construct a command that can be used to compare the two files.
  public struct DiffTool: Sendable, ExpressibleByStringLiteral {
    var tool: @Sendable (_ currentFilePath: String, _ failedFilePath: String) -> String

    public init(
      _ tool: @escaping @Sendable (_ currentFilePath: String, _ failedFilePath: String) -> String
    ) {
      self.tool = tool
    }

    public init(stringLiteral value: StringLiteralType) {
      self.tool = { "\(value) \($0) \($1)" }
    }

    /// The [Kaleidoscope](http://kaleidoscope.app) diff tool.
    public static let ksdiff = Self {
      "ksdiff \"\($0)\" \"\($1)\""
    }

    /// The default diff tool.
    public static let `default` = Self {
      """
      @\(minus)
      "file://\($0)"
      @\(plus)
      "file://\($1)"

      To configure output for a custom diff tool, use 'withSnapshotTesting'. For example:

          withSnapshotTesting(diffTool: .ksdiff) {
            // ...
          }
      """
    }

    public func callAsFunction(currentFilePath: String, failedFilePath: String) -> String {
      self.tool(currentFilePath, failedFilePath)
    }
  }
}

/// The ambient record mode: the innermost `.snapshots` trait if the test declares one, then the
/// `SNAPSHOT_TESTING_RECORD` environment variable, then `.missing`.
var defaultRecordMode: SnapshotTestingConfiguration.Record {
  #if canImport(Testing)
    if let test = Test.current {
      for trait in test.traits.reversed() {
        if let record = (trait as? _SnapshotsTestTrait)?.configuration.record {
          return record
        }
      }
    }
  #endif
  return environmentRecordMode
}

private let environmentRecordMode: SnapshotTestingConfiguration.Record = {
  if let value = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"],
    let record = SnapshotTestingConfiguration.Record(rawValue: value)
  {
    return record
  }
  return .missing
}()

/// The ambient diff tool: the innermost `.snapshots` trait if the test declares one, then
/// ``SnapshotTestingConfiguration/DiffTool-swift.struct/default``.
var defaultDiffTool: SnapshotTestingConfiguration.DiffTool {
  #if canImport(Testing)
    if let test = Test.current {
      for trait in test.traits.reversed() {
        if let diffTool = (trait as? _SnapshotsTestTrait)?.configuration.diffTool {
          return diffTool
        }
      }
    }
  #endif
  return .default
}

#if canImport(Testing)
  /// A type representing the configuration of snapshot testing.
  public struct _SnapshotsTestTrait: SuiteTrait, TestTrait {
    public let isRecursive = true
    let configuration: SnapshotTestingConfiguration
  }

  extension Trait where Self == _SnapshotsTestTrait {
    /// Configure snapshot testing in a suite or test.
    public static var snapshots: Self {
      snapshots()
    }

    /// Configure snapshot testing in a suite or test.
    ///
    /// - Parameters:
    ///   - record: The record mode of the test.
    ///   - diffTool: The diff tool to use in failure messages.
    public static func snapshots(
      record: SnapshotTestingConfiguration.Record? = nil,
      diffTool: SnapshotTestingConfiguration.DiffTool? = nil
    ) -> Self {
      _SnapshotsTestTrait(
        configuration: SnapshotTestingConfiguration(
          record: record,
          diffTool: diffTool
        )
      )
    }

    /// Configure snapshot testing in a suite or test.
    ///
    /// - Parameter configuration: The configuration to use.
    public static func snapshots(
      _ configuration: SnapshotTestingConfiguration
    ) -> Self {
      _SnapshotsTestTrait(configuration: configuration)
    }
  }

  extension _SnapshotsTestTrait: TestScoping {
    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: () async throws -> Void
    ) async throws {
      try await withSnapshotTesting(
        record: configuration.record,
        diffTool: configuration.diffTool
      ) {
        try await File.$counter.withValue(File.Counter()) {
          try await function()
        }
      }
    }
  }
#endif
