#if canImport(Testing)
  import Testing
  import InlineSnapshotTesting
  import SnapshotTestingCustomDump

  extension BaseSuite {
    @MainActor
    struct CustomDumpSnapshotTests {
      @Test func basics() async {
        struct User { let id: Int, name: String, bio: String }
        let user = User(id: 1, name: "Blobby", bio: "Blobbed around the world.")
        await assertInlineSnapshot(of: user, as: .customDump()) {
          """
          BaseSuite.CustomDumpSnapshotTests.User(
            id: 1,
            name: "Blobby",
            bio: "Blobbed around the world."
          )
          """
        }
      }
    }
  }
#endif
