import AppKit
import SwiftUI

/// Settings block that installs Jotley's agent skill beside the MCP connection steps.
/// Shared Protomota layout; the sandboxed app asks once for each agent folder.
struct AgentSkillSection: View {
    private let installer = AgentSkillInstaller(app: "Jotley", skillID: "jotley-mcp")
    @State private var statuses: [AgentSkillInstaller.Status] = []
    @State private var busy: AgentSkillInstaller.Agent?
    @State private var failures: [AgentSkillInstaller.Agent: String] = [:]
    @State private var installedThisSession = false
    @State private var replacing: AgentSkillInstaller.Status?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent skill").font(.headline)
                Text("Teaches your agent Jotley’s tools and when to use them.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if installer == nil {
                Text("This build doesn’t include the skill.").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(statuses, id: \.agent) { status in
                    row(status)
                    if status.agent != statuses.last?.agent { Divider() }
                }
            }
            HStack(spacing: 14) {
                if installedThisSession {
                    Text("New agent sessions will load it.").font(.callout).foregroundStyle(.secondary)
                }
                Button("Show in Finder", action: showInFinder).font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .alert("Replace the jotley-mcp skill?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
            Button("Cancel", role: .cancel) { replacing = nil }
            Button("Replace") {
                if let status = replacing { install(status.agent, replacing: true) }
                replacing = nil
            }
        } message: { Text("The existing folder moves to the Trash.") }
    }

    private func row(_ status: AgentSkillInstaller.Status) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(status.agent.title)
                Text(caption(status))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status.location.path)
                if let failure = failures[status.agent] {
                    Text(failure).font(.caption).foregroundStyle(Color.red).lineLimit(1).help(failure)
                }
            }
            Spacer(minLength: 12)
            trailing(status)
        }
        .padding(.vertical, 9)
        .opacity(dimmed(status) ? 0.6 : 1)
    }

    @ViewBuilder private func trailing(_ status: AgentSkillInstaller.Status) -> some View {
        if busy == status.agent {
            ProgressView().controlSize(.small).accessibilityLabel("Installing")
        } else if let installer, !installer.hasAccess(status.agent) {
            Button("Install…") { install(status.agent) }
                .accessibilityLabel("Install the Jotley skill for \(status.agent.title)")
                .disabled(busy != nil)
        } else {
            switch status.state {
            case .installed:
                Label("Installed", systemImage: "checkmark").foregroundStyle(.secondary)
            case .plugin:
                Label("Installed by Claude plugin", systemImage: "checkmark").foregroundStyle(.secondary)
            case .updateAvailable:
                Button("Update") { install(status.agent) }.disabled(busy != nil)
            case .differentVersion:
                HStack(spacing: 8) {
                    Text("Different skill found").foregroundStyle(.secondary)
                    Button("Replace…") { replacing = status }.disabled(busy != nil)
                }
            case .notInstalled:
                Button("Install") { install(status.agent) }
                    .accessibilityLabel("Install the Jotley skill for \(status.agent.title)")
                    .disabled(busy != nil || installer == nil)
            }
        }
    }

    private func dimmed(_ status: AgentSkillInstaller.Status) -> Bool {
        guard let installer, installer.hasAccess(status.agent) else { return false }
        return !status.agentFound && status.state == .notInstalled
    }

    private func caption(_ status: AgentSkillInstaller.Status) -> String {
        if case .plugin(let name) = status.state { return "Claude plugin \(name)" }
        let path = status.location.path.replacingOccurrences(of: AgentSkillInstaller.userHome.path, with: "~")
        if dimmed(status) { return "Not found on this Mac · \(path)" }
        return status.shared ? "\(path) · shared with \(status.agent == .codex ? "Gemini CLI" : "Codex")" : path
    }

    private func refresh() {
        guard let installer else { statuses = []; return }
        statuses = installer.withAccess { installer.statuses() }
    }

    private func install(_ agent: AgentSkillInstaller.Agent, replacing: Bool = false) {
        guard let installer, busy == nil else { return }
        failures[agent] = nil
        if !installer.hasAccess(agent) {
            guard grantAccess(agent, installer: installer) else { return }
            refresh()
            // A skill already there after the grant is left alone until the person chooses again.
            if statuses.first(where: { $0.agent == agent })?.state != .notInstalled { return }
        }
        busy = agent
        Task {
            defer { busy = nil; refresh() }
            do {
                try installer.withAccess { try installer.install(agent, replacing: replacing) }
                installedThisSession = true
            } catch {
                failures[agent] = error.localizedDescription
            }
        }
    }

    /// The App Sandbox needs one explicit grant of the agent's folder, chosen in an open panel.
    private func grantAccess(_ agent: AgentSkillInstaller.Agent, installer: AgentSkillInstaller) -> Bool {
        let folder = installer.accessFolder(agent)
        let exists = FileManager.default.fileExists(atPath: folder.path)
        let panel = NSOpenPanel()
        panel.title = "Allow Jotley to add its skill"
        panel.message = exists
            ? "Choose the \(folder.lastPathComponent) folder so Jotley can add its skill for \(agent.title)."
            : "Choose your home folder so Jotley can create \(folder.lastPathComponent) and add its skill for \(agent.title)."
        panel.prompt = "Allow"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = exists ? folder : AgentSkillInstaller.userHome
        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        guard installer.rememberGrant(chosen, for: agent) else {
            failures[agent] = "Choose \(folder.path) or your home folder."
            return false
        }
        return true
    }

    private func showInFinder() {
        let installed = statuses.first { status in
            if case .installed = status.state { return true }
            return status.state == .updateAvailable || status.state == .differentVersion
        }?.location.appending(path: "SKILL.md")
        guard let url = installed ?? AgentSkillInstaller.bundledSkill() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
