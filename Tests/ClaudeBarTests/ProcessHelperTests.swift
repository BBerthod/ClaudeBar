import XCTest
import Darwin
@testable import ClaudeBarLib

final class ProcessHelperTests: XCTestCase {
    func testLikelyClaudeExecutables() {
        for path in ["/usr/local/bin/claude", "/opt/Claude/bin/CLI", "/usr/bin/node", "/opt/bin/NODE"] {
            XCTAssertTrue(ProcessHelper.isLikelyClaudeProcess(executablePath: path), path)
        }
    }

    func testUnrelatedAndEmptyExecutablePaths() {
        for path in ["", "/usr/bin/python3", "/bin/zsh", "/usr/bin/sleep"] {
            XCTAssertFalse(ProcessHelper.isLikelyClaudeProcess(executablePath: path), path)
        }
    }

    func testExecutablePathLookup() throws {
        let path = try XCTUnwrap(ProcessHelper.executablePath(for: getpid()))
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        XCTAssertNil(ProcessHelper.executablePath(for: -1))
        XCTAssertNil(ProcessHelper.executablePath(for: 0))
    }
}
