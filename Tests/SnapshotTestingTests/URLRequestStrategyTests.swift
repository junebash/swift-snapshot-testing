import Foundation
import Testing

@testable import SnapshotTesting

/// Byte-identity checks against the legacy suite's recorded references for `testURLRequest`. These
/// prove the ported `.raw`/`.curl` strategies produce output indistinguishable from the
/// closure-based `Snapshotting<Value, Format>` witnesses they replace — not merely output that
/// looks plausible.
@Suite @MainActor struct URLRequestStrategyTests {
  /// The directory holding the legacy suite's recorded reference files.
  static let legacySnapshotsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SnapshotTestingTests
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("SnapshotTestingTests/__Snapshots__/SnapshotTestingTests")

  /// The exact GET request that produced `testURLRequest.get.txt` / `testURLRequest.get-curl.txt`
  /// in the legacy suite.
  static func makeGetRequest() throws -> URLRequest {
    var request = URLRequest(url: try #require(URL(string: "https://www.pointfree.co/")))
    request.addValue("pf_session={}", forHTTPHeaderField: "Cookie")
    request.addValue("text/html", forHTTPHeaderField: "Accept")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  /// The exact POST request that produced `testURLRequest.post.txt` /
  /// `testURLRequest.post-curl.txt` in the legacy suite.
  static func makePostRequest() throws -> URLRequest {
    var request = URLRequest(
      url: try #require(URL(string: "https://www.pointfree.co/subscribe")))
    request.httpMethod = "POST"
    request.addValue("pf_session={\"user_id\":\"0\"}", forHTTPHeaderField: "Cookie")
    request.addValue("text/html", forHTTPHeaderField: "Accept")
    request.httpBody = Data("pricing[billing]=monthly&pricing[lane]=individual".utf8)
    return request
  }

  /// The exact GET-with-query request that produced `testURLRequest.get-with-query.txt` /
  /// `testURLRequest.get-with-query-curl.txt`. This is the only case that exercises the query-item
  /// sorting in `sortingQueryItems()` — the sole non-trivial branch of the port — so byte-identity
  /// here is what proves that logic was ported faithfully (the unsorted input must come back sorted).
  static func makeGetWithQueryRequest() throws -> URLRequest {
    var request = URLRequest(
      url: try #require(
        URL(string: "https://www.pointfree.co?key_2=value_2&key_1=value_1&key_3=value_3")))
    request.addValue("pf_session={}", forHTTPHeaderField: "Cookie")
    request.addValue("text/html", forHTTPHeaderField: "Accept")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  /// The exact HEAD request that produced `testURLRequest.head.txt` /
  /// `testURLRequest.head-curl.txt` in the legacy suite.
  static func makeHeadRequest() throws -> URLRequest {
    var request = URLRequest(url: try #require(URL(string: "https://www.pointfree.co/")))
    request.httpMethod = "HEAD"
    request.addValue("pf_session={}", forHTTPHeaderField: "Cookie")
    return request
  }

  private func reference(_ name: String) throws -> Data {
    try Data(contentsOf: Self.legacySnapshotsURL.appendingPathComponent(name))
  }

  @Test func getRawMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.get.txt")
    let recorded = await _recordSnapshot(of: try Self.makeGetRequest(), as: .raw)
    #expect(recorded == reference)
  }

  @Test func getCurlMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.get-curl.txt")
    let recorded = await _recordSnapshot(of: try Self.makeGetRequest(), as: .curl)
    #expect(recorded == reference)
  }

  @Test func getWithQueryRawMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.get-with-query.txt")
    let recorded = await _recordSnapshot(of: try Self.makeGetWithQueryRequest(), as: .raw)
    #expect(recorded == reference)
  }

  @Test func getWithQueryCurlMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.get-with-query-curl.txt")
    let recorded = await _recordSnapshot(of: try Self.makeGetWithQueryRequest(), as: .curl)
    #expect(recorded == reference)
  }

  @Test func postRawMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.post.txt")
    let recorded = await _recordSnapshot(of: try Self.makePostRequest(), as: .raw)
    #expect(recorded == reference)
  }

  @Test func postCurlMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.post-curl.txt")
    let recorded = await _recordSnapshot(of: try Self.makePostRequest(), as: .curl)
    #expect(recorded == reference)
  }

  @Test func headRawMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.head.txt")
    let recorded = await _recordSnapshot(of: try Self.makeHeadRequest(), as: .raw)
    #expect(recorded == reference)
  }

  @Test func headCurlMatchesLegacyReferenceByteForByte() async throws {
    let reference = try reference("testURLRequest.head-curl.txt")
    let recorded = await _recordSnapshot(of: try Self.makeHeadRequest(), as: .curl)
    #expect(recorded == reference)
  }
}
