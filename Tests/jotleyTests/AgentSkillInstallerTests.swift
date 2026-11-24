import XCTest
@testable import jotley

final class AgentSkillInstallerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "skill-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    private func skill(_ text: String, app: String = "Jotley") -> AgentSkillInstaller {
        AgentSkillInstaller(app: app, skillID: "jotley-mcp", version: "1", instructions: Data(text.utf8), home: home)
    }

    func testInstallsUpdatesAndSharesCopy() throws {
        try skill("old").install(.claudeCode)
        XCTAssertEqual(skill("new").status(.claudeCode).state, .updateAvailable)
        try skill("new").install(.claudeCode)
        XCTAssertEqual(skill("new").status(.claudeCode).state, .installed)
        try skill("new").install(.codex)
        let gemini = skill("new").status(.gemini)
        XCTAssertEqual(gemini.state, .installed)
        XCTAssertTrue(gemini.shared)
    }

    func testKeepsAnotherCopyUnlessReplacing() throws {
        try skill("other", app: "Other").install(.claudeCode)
        XCTAssertEqual(skill("new").status(.claudeCode).state, .differentVersion)
        XCTAssertThrowsError(try skill("new").install(.claudeCode))
        try skill("new").install(.claudeCode, replacing: true)
        XCTAssertEqual(skill("new").status(.claudeCode).state, .installed)
    }

    func testBundledSkillIsJotleyMCP() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "macOS/Resources/AgentSkill.md")
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).hasPrefix("---\nname: jotley-mcp\n"))
    }
}
