#if canImport(Testing)
  import Testing
  import SnapshotTesting

  // Explicit types: the async engine's `.snapshots` trait is transitively visible here until the
  // flip removes the legacy one, making the unqualified spelling ambiguous.
  @Suite(
    .snapshots(
      record: SnapshotTesting.SnapshotTestingConfiguration.Record.failed,
      diffTool: SnapshotTesting.SnapshotTestingConfiguration.DiffTool.ksdiff))
  struct BaseSuite {
  }
#endif
