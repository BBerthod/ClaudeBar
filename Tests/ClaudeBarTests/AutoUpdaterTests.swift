import XCTest
@testable import ClaudeBarLib

final class AutoUpdaterTests: XCTestCase {
    func testUpdateScriptStagesBesideTargetAndRollsBackFailedSwap() {
        let script = AutoUpdater.updateScript(
            stagingApp: URL(fileURLWithPath: "/tmp/ClaudeBar update/ClaudeBar.app"),
            targetApp: URL(fileURLWithPath: "/Users/Test User/Applications/ClaudeBar.app")
        )

        XCTAssertTrue(script.contains("source_app='/tmp/ClaudeBar update/ClaudeBar.app'"))
        XCTAssertTrue(script.contains("target_app='/Users/Test User/Applications/ClaudeBar.app'"))
        XCTAssertTrue(script.contains("new_app='/Users/Test User/Applications/ClaudeBar.app.new'"))
        XCTAssertTrue(script.contains("backup_app='/Users/Test User/Applications/ClaudeBar.app.bak'"))
        XCTAssertTrue(script.contains("cp -R \"$source_app\" \"$new_app\""))
        XCTAssertTrue(script.contains("mv \"$backup_app\" \"$target_app\""))
        XCTAssertTrue(script.contains("if ! mv \"$new_app\" \"$target_app\"; then\n    rollback"))
    }

    func testUpdateScriptRemovesBackupOnlyAfterSuccessfulSwap() {
        let script = AutoUpdater.updateScript(
            stagingApp: URL(fileURLWithPath: "/tmp/ClaudeBar-update/ClaudeBar.app"),
            targetApp: URL(fileURLWithPath: "/Applications/ClaudeBar.app")
        )

        let backupCreation = try! XCTUnwrap(script.range(of: "mv \"$target_app\" \"$backup_app\""))
        let successfulSwap = try! XCTUnwrap(script.range(of: "if ! mv \"$new_app\" \"$target_app\"; then"))
        let open = try! XCTUnwrap(script.range(of: "open \"$target_app\""))
        let removals = script.ranges(of: "rm -rf \"$backup_app\"")

        // Only the stale-backup cleanup (before the swap) and the final cleanup
        // (after a successful swap) may delete the backup — never in between.
        XCTAssertEqual(removals.count, 2)
        XCTAssertLessThan(removals[0].lowerBound, backupCreation.lowerBound)
        XCTAssertLessThan(successfulSwap.lowerBound, removals[1].lowerBound)
        XCTAssertLessThan(removals[1].lowerBound, open.lowerBound)
    }

    func testUpdateScriptShellQuotesPathsContainingApostrophes() {
        let script = AutoUpdater.updateScript(
            stagingApp: URL(fileURLWithPath: "/tmp/Developer's Build/ClaudeBar.app"),
            targetApp: URL(fileURLWithPath: "/Users/O'Neil/My Apps/ClaudeBar.app")
        )

        XCTAssertTrue(script.contains("source_app='/tmp/Developer'\\''s Build/ClaudeBar.app'"))
        XCTAssertTrue(script.contains("target_app='/Users/O'\\''Neil/My Apps/ClaudeBar.app'"))
    }

    func testReplaceableBundleValidation() {
        XCTAssertTrue(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/Applications/ClaudeBar.app")
        ))
        XCTAssertTrue(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/Users/test/My Applications/ClaudeBar.app")
        ))

        XCTAssertFalse(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/Applications/ClaudeBar")
        ))
        XCTAssertFalse(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/Applications/ClaudeBar.APP")
        ))
        XCTAssertFalse(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/tmp/ClaudeBar.app")
        ))
        XCTAssertFalse(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/private/tmp/ClaudeBar.app")
        ))
        XCTAssertFalse(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/Users/test/project/.build/debug/ClaudeBar.app")
        ))
        XCTAssertFalse(AutoUpdater.isReplaceableBundle(
            URL(fileURLWithPath: "/Users/test/project/build/release/ClaudeBar.app")
        ))
    }
}
