import Testing
@testable import ClaudeBarLib

@MainActor
struct UpdateCheckServiceTests {

    @Test func testNewerMajorVersion() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "2.0.0", current: "1.9.9") == true)
    }

    @Test func testOlderMajorVersion() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "1.0.0", current: "2.0.0") == false)
    }

    @Test func testNewerMinorVersion() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "1.1.0", current: "1.0.9") == true)
    }

    @Test func testNewerPatchVersion() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "0.6.1", current: "0.6.0") == true)
    }

    @Test func testSameVersion() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "1.0.0", current: "1.0.0") == false)
    }

    @Test func testOlderPatchVersion() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "0.5.9", current: "0.6.0") == false)
    }

    @Test func testDifferentLengths() async throws {
        let service = UpdateCheckService()
        // "1.0" vs "1.0.0" — missing parts default to 0, so equal → false
        #expect(service.isNewer(remote: "1.0", current: "1.0.0") == false)
    }

    @Test func testRemoteHasMoreParts() async throws {
        let service = UpdateCheckService()
        // "1.0.1" vs "1.0" — remote patch 1 > current implicit 0 → true
        #expect(service.isNewer(remote: "1.0.1", current: "1.0") == true)
    }

    @Test func testPrereleaseSuffixIsIgnored() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "1.2-beta.3", current: "1.1.9") == true)
        #expect(service.isNewer(remote: "1.2-beta.3", current: "1.2.0") == false)
    }

    @Test func testNonNumericSegmentInvalidatesComparison() async throws {
        let service = UpdateCheckService()
        #expect(service.isNewer(remote: "1.beta.3", current: "1.0.0") == false)
    }
}
