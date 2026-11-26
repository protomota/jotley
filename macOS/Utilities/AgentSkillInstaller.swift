// Shared Protomota agent skill installer. Keep this file identical in every Protomota Mac app
// (Inkspring, Glimmer, Jotley, Textley, OpenTalon); only the bundled SKILL.md differs.
import Foundation

struct AgentSkillInstaller {
    enum Agent: String, CaseIterable, Identifiable, Sendable {
        case claudeCode, codex, gemini
        var id: Self { self }
        var title: String {
            switch self { case .claudeCode: "Claude Code"; case .codex: "Codex"; case .gemini: "Gemini CLI" }
        }
    }

    enum State: Equatable, Sendable {
        case notInstalled
        case installed
        case updateAvailable
        case differentVersion
        case plugin(String)
    }

    struct Status: Equatable, Sendable {
        let agent: Agent
        let state: State
        /// The folder that holds the skill, or the folder an install would create.
        let location: URL
        /// Codex and Gemini CLI both read ~/.agents/skills, so one copy serves both.
        let shared: Bool
        /// False when the agent's own folders are missing from this Mac.
        let agentFound: Bool
    }

    let app: String
    let skillID: String
    let instructions: Data
    let license: Data?
    let home: URL

    init(app: String, skillID: String, instructions: Data, license: Data? = nil,
         home: URL = AgentSkillInstaller.userHome) {
        self.app = app
        self.skillID = skillID
        self.instructions = instructions
        self.license = license
        self.home = home
    }

    /// The bundled skill's `metadata.version`, the number every copy is compared against.
    var version: String? { Self.frontMatter(instructions).version }

    /// Loads the bundled skill: AgentSkill.md (the SKILL.md) and AgentSkill-LICENSE.txt in the app's resources.
    init?(app: String, skillID: String, bundle: Bundle = .main, home: URL = AgentSkillInstaller.userHome) {
        guard let file = Self.bundledSkill(bundle), let instructions = try? Data(contentsOf: file) else { return nil }
        let license = bundle.url(forResource: "AgentSkill-LICENSE", withExtension: "txt").flatMap { try? Data(contentsOf: $0) }
        self.init(app: app, skillID: skillID, instructions: instructions, license: license, home: home)
    }

    static func bundledSkill(_ bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "AgentSkill", withExtension: "md")
    }

    /// The signed-in user's real home folder, also inside the App Sandbox.
    static var userHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Skill folders each agent reads, in the order the agent prefers them.
    func searchFolders(_ agent: Agent) -> [URL] {
        switch agent {
        case .claudeCode: [folder(".claude", "skills")]
        case .codex: [folder(".agents", "skills"), folder(".codex", "skills")]
        case .gemini: [folder(".agents", "skills"), folder(".gemini", "skills"), folder(".gemini", "config", "skills")]
        }
    }

    /// Where this app installs: Claude Code's folder, or the folder Codex and Gemini CLI share.
    func installFolder(_ agent: Agent) -> URL {
        agent == .claudeCode ? folder(".claude", "skills") : folder(".agents", "skills")
    }

    func status(_ agent: Agent) -> Status {
        let found = agentFound(agent)
        for parent in searchFolders(agent) {
            let candidate = parent.appending(path: skillID, directoryHint: .isDirectory)
            guard exists(candidate) else { continue }
            return Status(agent: agent, state: classify(candidate), location: candidate,
                          shared: agent != .claudeCode && parent == folder(".agents", "skills"), agentFound: found)
        }
        if agent == .claudeCode, let plugin = claudePlugin() {
            return Status(agent: agent, state: .plugin(plugin), location: installFolder(agent).appending(path: skillID),
                          shared: false, agentFound: found)
        }
        return Status(agent: agent, state: .notInstalled, location: installFolder(agent).appending(path: skillID),
                      shared: agent != .claudeCode, agentFound: found)
    }

    func statuses() -> [Status] { Agent.allCases.map(status) }

    /// Installs or updates the bundled skill. An older copy of the same skill is replaced; a folder holding
    /// some other skill is replaced only when `replacing` is true. The old folder (or link) moves to the Trash.
    @discardableResult
    func install(_ agent: Agent, replacing: Bool = false) throws -> URL {
        let parent = installFolder(agent)
        let target = parent.appending(path: skillID, directoryHint: .isDirectory)
        let manager = FileManager.default
        if exists(target) {
            switch classify(target) {
            case .installed: return target
            case .updateAvailable: break
            default: guard replacing else { throw InstallError.differentVersion(target) }
            }
        }
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(path: ".\(skillID)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try instructions.write(to: staging.appending(path: "SKILL.md"))
            if let license { try license.write(to: staging.appending(path: "LICENSE")) }
            if exists(target) { try trash(target) }
            try manager.moveItem(at: staging, to: target)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
        return target
    }

    enum InstallError: LocalizedError {
        case differentVersion(URL)
        var errorDescription: String? {
            switch self {
            case .differentVersion(let url): "A different skill is already in \(url.path). Choose Replace to use this one."
            }
        }
    }

    // MARK: - App Sandbox access

    /// True in sandboxed apps (Glimmer, Jotley), which can read and write an agent's folder only
    /// after the person grants it once in an open panel. Unsandboxed apps never ask.
    static var isSandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    /// The folder a sandboxed app needs for an agent: ~/.claude, or ~/.agents for Codex and Gemini CLI.
    func accessFolder(_ agent: Agent) -> URL { agent == .claudeCode ? folder(".claude") : folder(".agents") }

    /// Whether a saved grant covers this agent's folder (a grant of the home folder covers both).
    func hasAccess(_ agent: Agent) -> Bool {
        !Self.isSandboxed || Self.grants().contains { accessFolder(agent).path.hasPrefix($0.path) }
    }

    /// Saves a folder the person chose in an open panel. Returns false for a folder that doesn't cover the agent.
    @discardableResult
    func rememberGrant(_ chosen: URL, for agent: Agent) -> Bool {
        let target = accessFolder(agent).standardizedFileURL.path
        guard target.hasPrefix(chosen.standardizedFileURL.path),
              let bookmark = try? chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                      relativeTo: nil) else { return false }
        var saved = UserDefaults.standard.dictionary(forKey: Self.grantsKey) as? [String: Data] ?? [:]
        saved[chosen.standardizedFileURL.path] = bookmark
        UserDefaults.standard.set(saved, forKey: Self.grantsKey)
        return true
    }

    /// Runs `body` with every saved grant open, so detection and installs can reach the agent folders.
    func withAccess<T>(_ body: () throws -> T) rethrows -> T {
        let opened = Self.grants().filter { $0.startAccessingSecurityScopedResource() }
        defer { opened.forEach { $0.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    private static let grantsKey = "agentSkillFolderGrants"

    private static func grants() -> [URL] {
        guard isSandboxed, let saved = UserDefaults.standard.dictionary(forKey: grantsKey) as? [String: Data] else { return [] }
        return saved.values.compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        }
    }

    // MARK: - Detection

    /// Same bytes, or the same skill at this version or newer: installed. The same skill at an older or
    /// unknown version, or a copy this app can't read (such as a link the App Sandbox can't follow): update.
    /// A folder whose SKILL.md names another skill: different.
    private func classify(_ candidate: URL) -> State {
        guard let installed = try? Data(contentsOf: candidate.appending(path: "SKILL.md")) else { return .updateAvailable }
        if installed == instructions { return .installed }
        let found = Self.frontMatter(installed)
        guard found.name == skillID else { return .differentVersion }
        guard let current = version, let other = found.version else { return .updateAvailable }
        return Self.compare(other, current) == .orderedAscending ? .updateAvailable : .installed
    }

    /// Reads `name` and `metadata.version` from a SKILL.md front matter block.
    static func frontMatter(_ data: Data) -> (name: String?, version: String?) {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }
        var name: String?, version: String?, inMetadata = false
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            let indented = line.first == " " || line.first == "\t"
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { inMetadata = !indented && parts.first == "metadata"; continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !indented { inMetadata = key == "metadata" && value.isEmpty }
            if !indented && key == "name" { name = value }
            if indented && inMetadata && key == "version" { version = value }
        }
        return (name, version)
    }

    /// Compares dotted version numbers numerically (1.10.0 is newer than 1.9.2).
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }, right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0, b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Claude Code plugins record their install folders; a matching plugin name or skill counts.
    private func claudePlugin() -> String? {
        let record = folder(".claude", "plugins").appending(path: "installed_plugins.json")
        guard let data = try? Data(contentsOf: record),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any] else { return nil }
        for (key, installs) in plugins {
            let name = String(key.split(separator: "@").first ?? Substring(key))
            if name == skillID || name.hasSuffix("-\(skillID)") { return name }
            for install in installs as? [[String: Any]] ?? [] {
                guard let path = install["installPath"] as? String else { continue }
                if exists(URL(filePath: path).appending(path: "skills/\(skillID)/SKILL.md")) { return name }
            }
        }
        return nil
    }

    private func agentFound(_ agent: Agent) -> Bool {
        switch agent {
        case .claudeCode: exists(folder(".claude"))
        case .codex: exists(folder(".codex")) || exists(folder(".agents"))
        case .gemini: exists(folder(".gemini"))
        }
    }

    private func folder(_ parts: String...) -> URL {
        parts.reduce(home) { $0.appending(path: $1, directoryHint: .isDirectory) }
    }

    private func exists(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func trash(_ url: URL) throws {
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch {
            // Folders outside a Trash-capable volume (or in tests) are moved aside instead of deleted.
            let aside = url.deletingLastPathComponent().appending(path: ".\(skillID)-replaced-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: url, to: aside)
        }
    }
}
