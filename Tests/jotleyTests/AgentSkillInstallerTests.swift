import XCTest
@testable import jotley

final class AgentSkillInstallerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "skill-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    private func text(_ version: String, name: String = "jotley-mcp", body: String = "body") -> String {
        "---\nname: \(name)\nmetadata:\n  version: \"\(version)\"\n---\n\(body)"
    }

    private func skill(_ version: String = "1.2.0") -> AgentSkillInstaller {
        AgentSkillInstaller(app: "Jotley", skillID: "jotley-mcp", instructions: Data(text(version).utf8), home: home)
    }

    private func write(_ contents: String, to parts: String...) throws {
        let folder = parts.reduce(home!) { $0.appending(path: $1) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: folder.appending(path: "SKILL.md"))
    }

    func testInstallsUpdatesAndSharesCopy() throws {
        try skill("1.1.0").install(.claudeCode)
        XCTAssertEqual(skill().status(.claudeCode).state, .updateAvailable)
        try skill().install(.claudeCode)
        XCTAssertEqual(skill().status(.claudeCode).state, .installed)
        try skill().install(.codex)
        let gemini = skill().status(.gemini)
        XCTAssertEqual(gemini.state, .installed)
        XCTAssertTrue(gemini.shared)
    }

    func testTreatsSameOrNewerVersionAsInstalled() throws {
        try write(text("1.10.0", body: "newer"), to: ".claude", "skills", "jotley-mcp")
        XCTAssertEqual(skill().status(.claudeCode).state, .installed)
        try write(text("1.2.0", body: "edited"), to: ".claude", "skills", "jotley-mcp")
        XCTAssertEqual(skill().status(.claudeCode).state, .installed)
    }

    func testKeepsAnotherSkillUnlessReplacing() throws {
        try write(text("9.0.0", name: "other-skill"), to: ".claude", "skills", "jotley-mcp")
        XCTAssertEqual(skill().status(.claudeCode).state, .differentVersion)
        XCTAssertThrowsError(try skill().install(.claudeCode))
        try skill().install(.claudeCode, replacing: true)
        XCTAssertEqual(skill().status(.claudeCode).state, .installed)
    }

    func testBundledSkillIsVersioned() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "macOS/Resources/AgentSkill.md")
        let data = try Data(contentsOf: file)
        XCTAssertEqual(AgentSkillInstaller.frontMatter(data).name, "jotley-mcp")
        XCTAssertNotNil(AgentSkillInstaller.frontMatter(data).version)
    }
}
