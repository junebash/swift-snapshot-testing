#if compiler(>=6) && canImport(Testing)
  import Testing
  @testable import SnapshotTesting

  extension BaseSuite {
    struct SnapshotsTraitTests {
      @Test(.snapshots(diffTool: "ksdiff"))
      func testDiffTool() {
        #expect(
          defaultDiffTool(currentFilePath: "old.png", failedFilePath: "new.png")
            == "ksdiff old.png new.png"
        )
      }

      @Suite(.snapshots(diffTool: "ksdiff"))
      struct OverrideDiffTool {
        @Test(.snapshots(diffTool: "difftool"))
        func testDiffToolOverride() {
          #expect(
            defaultDiffTool(currentFilePath: "old.png", failedFilePath: "new.png")
              == "difftool old.png new.png"
          )
        }

        @Suite(.snapshots(record: .all))
        struct OverrideRecord {
          @Test
          func config() {
            #expect(
              defaultDiffTool(currentFilePath: "old.png", failedFilePath: "new.png")
                == "ksdiff old.png new.png"
            )
            #expect(defaultRecordMode == .all)
          }

          @Suite(.snapshots(record: .failed, diffTool: "diff"))
          struct OverrideDiffToolAndRecord {
            @Test
            func config() {
              #expect(
                defaultDiffTool(currentFilePath: "old.png", failedFilePath: "new.png")
                  == "diff old.png new.png"
              )
              #expect(defaultRecordMode == .failed)
            }
          }
        }
      }
    }
  }
#endif
