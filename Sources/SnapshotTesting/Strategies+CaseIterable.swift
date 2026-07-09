/// A strategy that snapshots a *function* `(Input) -> Output` by feeding it every case of a
/// `CaseIterable` input and recording each input/output pair as a CSV row.
///
/// Unlike the pure value strategies, this one *composes* another strategy — `witness` renders each
/// output to a string. It is therefore modeled as a dedicated type rather than a closure pullback:
/// storing the witness as a property keeps it inside this strategy's isolation domain, avoiding the
/// cross-actor capture that a `@MainActor` transform closure would require (and which would force an
/// unwanted `Sendable` bound on the witness). Rendering each output can suspend, so ``snapshot(of:)``
/// awaits the witness per case.
public struct _CaseIterableFuncStrategy<Input: CaseIterable, Witness: SnapshotStrategy>:
  SnapshotStrategy
where Witness.Format == String, Witness.Value: Sendable {
  public typealias Value = (Input) -> Witness.Value
  public typealias Format = String
  public typealias Diffing = LinesDiffing

  let witness: Witness

  public var pathExtension: String? { "csv" }
  public var diffing: LinesDiffing { LinesDiffing() }

  public nonisolated(nonsending) func snapshot(
    of value: sending (Input) -> Witness.Value
  ) async -> sending String {
    var rows: [String] = []
    for input in Input.allCases {
      let output = await witness.snapshot(of: value(input))
      rows.append("\"\(input)\",\"\(output)\"")
    }
    return rows.joined(separator: "\n")
  }
}

extension SnapshotStrategy {
  /// A strategy for snapshotting the output for every input of a function. The snapshot is a
  /// comma-separated value (CSV) file mapping each `CaseIterable` input to its rendered output.
  ///
  /// - Parameter witness: A strategy for snapshotting the function's output.
  /// - Returns: A strategy on functions `(Input) -> Output` that feeds every possible input into
  ///   the function and records the output into a CSV file.
  ///
  /// ```swift
  /// enum Direction: String, CaseIterable {
  ///   case up, down, left, right
  ///   var rotatedLeft: Direction { … }
  /// }
  ///
  /// await assertSnapshot(of: { $0.rotatedLeft }, as: .func(into: .description()))
  /// ```
  ///
  /// Records:
  ///
  /// ```csv
  /// "up","left"
  /// "down","right"
  /// "left","down"
  /// "right","up"
  /// ```
  public static func `func`<Input, Witness>(
    into witness: Witness
  ) -> _CaseIterableFuncStrategy<Input, Witness>
  where Self == _CaseIterableFuncStrategy<Input, Witness>, Witness.Value: Sendable {
    _CaseIterableFuncStrategy(witness: witness)
  }
}
