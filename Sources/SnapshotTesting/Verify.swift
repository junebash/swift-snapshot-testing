import Foundation

// Internal validation helpers used by tests to exercise strategies against reference bytes during
// the migration, before the public async `assertSnapshot` exists. Not part of the public API.

/// Captures `value` with `strategy` and returns the diff against previously-recorded `reference`
/// bytes. `nil` means the capture matches the reference.
@MainActor
func _verifySnapshot<S: SnapshotStrategy>(
  of value: sending S.Value,
  as strategy: S,
  reference: Data
) async throws -> SnapshotDifference? {
  let captured = await strategy.snapshot(of: value)
  let referenceValue = try strategy.diffing.value(from: reference)
  return strategy.diffing.diff(referenceValue, captured)
}

/// Captures `value` with `strategy` and returns the reference bytes that would be recorded for it.
@MainActor
func _recordSnapshot<S: SnapshotStrategy>(
  of value: sending S.Value,
  as strategy: S
) async -> Data {
  let captured = await strategy.snapshot(of: value)
  return strategy.diffing.data(from: captured)
}
