import Testing
@testable import ClaudeBarLib

struct RecentSessionsMetadataTests {

    @Test func extractsCwdGitBranchAndStringSummary() {
        let lines = [
            #"{"type":"user","cwd":"/Users/me/Dev/myproj","gitBranch":"main","message":{"content":"Fix the bug"}}"#
        ]

        let metadata = SessionService.sessionMetadata(fromLines: lines)

        #expect(metadata.cwd == "/Users/me/Dev/myproj")
        #expect(metadata.gitBranch == "main")
        #expect(metadata.summary == "Fix the bug")
    }

    @Test func extractsSummaryFromArrayContent() {
        let lines = [
            #"{"type":"user","message":{"content":[{"type":"text","text":"Hello world"}]}}"#
        ]

        let metadata = SessionService.sessionMetadata(fromLines: lines)

        #expect(metadata.summary == "Hello world")
    }

    @Test func truncatesSummaryToOneHundredCharacters() {
        let prompt = String(repeating: "x", count: 120)
        let lines = [
            #"{"type":"user","message":{"content":"\#(prompt)"}}"#
        ]

        let metadata = SessionService.sessionMetadata(fromLines: lines)

        #expect(metadata.summary == String(repeating: "x", count: 100))
    }

    @Test func treatsEmptyGitBranchAsNil() {
        let lines = [
            #"{"type":"user","cwd":"/Users/me/Dev/myproj","gitBranch":"","message":{"content":"Fix the bug"}}"#
        ]

        let metadata = SessionService.sessionMetadata(fromLines: lines)

        #expect(metadata.gitBranch == nil)
    }

    @Test func extractsCwdFromAssistantLineWithoutUserSummary() {
        let lines = [
            #"{"type":"assistant","cwd":"/Users/me/Dev/myproj","message":{"content":"Done"}}"#
        ]

        let metadata = SessionService.sessionMetadata(fromLines: lines)

        #expect(metadata.cwd == "/Users/me/Dev/myproj")
        #expect(metadata.summary == nil)
    }

    @Test func emptyLinesReturnNilMetadata() {
        let metadata = SessionService.sessionMetadata(fromLines: [])

        #expect(metadata.cwd == nil)
        #expect(metadata.gitBranch == nil)
        #expect(metadata.summary == nil)
    }

    @Test func decodesEncodedProjectDirectoryNameToPath() {
        #expect(SessionService.dirNameToPath("/x/-Users-me-Dev-proj") == "/Users/me/Dev/proj")
    }
}
