import AppKit
import SwiftUI

extension SettingsView {
    var mcpDesktopSetup: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose your Mac app").font(.headline)
            Picker("Connect to", selection: $mcpClient) {
                Text("Claude Code app").tag("Claude Code app")
                Text("Codex app").tag("Codex app")
                Text("Claude chat · advanced").tag("Claude chat")
            }.pickerStyle(.segmented).labelsHidden()
                .onChange(of: mcpClient) { _, _ in mcpCopiedItem = nil; mcpSetupMessage = nil }

            if mcpClient == "Claude Code app" {
                mcpSetupStep(1, title: "Save a connection in your project", detail: "Choose the folder you work in. Jotley adds its entry to that folder’s .mcp.json and preserves other servers. The connection uses this copy of Jotley, with no access token in the project file.") {
                    Button("Save project connection…") {
                        guard let configuration = JotleyMCPDesktopSetup.projectConfiguration else { return }
                        runMCPSetup { try JotleyMCPDesktopSetup.saveProject(configuration: configuration) }
                    }.disabled(!mcp.enabled).accessibilityIdentifier("mcpSaveClaudeProject")
                }
                mcpSetupStep(2, title: "Open Claude’s Code tab", detail: "In the Claude Mac app, select Code. Start a new local session on This computer and choose that same project folder. Review Claude’s project MCP trust prompt.") {
                    Button("Open Claude") { openMCPClient("com.anthropic.claudefordesktop", name: "Claude") }
                }
                mcpSetupStep(3, title: "Check Connectors in the local session", detail: "Open the session’s Connectors panel and check Jotley. If the project was already open, start a new session. Regular Claude chat uses the separate Claude chat setup here.") { mcpTryPrompt }
                Link("Claude Code desktop guide", destination: URL(string: "https://code.claude.com/docs/en/desktop#connect-external-tools")!)
            } else if mcpClient == "Codex app" {
                mcpSetupStep(1, title: "Add an MCP server in Codex", detail: "Open Codex for Mac. Go to Settings → MCP servers → Add server. Name the server jotley and choose STDIO.") {
                    Button("Open Codex") { openMCPClient("com.openai.codex", name: "Codex") }
                }
                mcpSetupStep(2, title: "Paste the two connection fields", detail: "Paste Command as a path, without extra quotes. Add one Argument and paste its value below. Leave Environment variables empty. Jotley’s bundled bridge handles the connection; no separate runtime or token is needed.") {
                    VStack(alignment: .leading, spacing: 10) {
                        mcpCopyField("Command", value: JotleyMCPDesktopSetup.command, item: "commandPath")
                        mcpCopyField("Argument", value: JotleyMCPDesktopSetup.argument, item: "argument")
                    }
                }
                mcpSetupStep(3, title: "Save, restart and check", detail: "Click Save, then Restart for the server. Start a local chat and type /mcp to check Jotley. Some current versions label the desktop app ChatGPT. Keep Jotley open and in its current location.") { mcpTryPrompt }
                Link("Codex desktop MCP guide", destination: URL(string: "https://learn.chatgpt.com/docs/extend/mcp?surface=desktop")!)
            } else {
                mcpSetupStep(1, title: "Save the Claude chat extension", detail: "This is for regular Claude chat in the Mac app. Claude supplies the runtime, so there is nothing to install in Terminal. The saved extension contains no access token.") {
                    Button("Save Claude extension…") { runMCPSetup { try JotleyMCPDesktopSetup.saveClaudeExtension(endpoint: mcp.endpoint) } }
                        .disabled(!mcp.enabled).accessibilityIdentifier("mcpSaveClaudeExtension")
                }
                mcpSetupStep(2, title: "Install it in Claude’s local extensions", detail: "Open Claude → Settings → Desktop app → Extensions → Manage → Advanced settings → Install Extension…. Choose Jotley.mcpb and follow the prompts. Older versions start at Settings → Extensions.") {
                    Button("Open Claude") { openMCPClient("com.anthropic.claudefordesktop", name: "Claude") }
                }
                mcpSetupStep(3, title: "Paste your token and connect", detail: "In the extension’s Jotley access token field, paste the token copied here and save. Start a new chat and check Jotley under + → Connectors. Keep Jotley open.") {
                    Button(mcpCopiedItem == "token" ? "Token copied ✓" : "Copy access token") { copyMCP(mcp.accessToken, item: "token") }
                        .disabled(!mcp.enabled).accessibilityIdentifier("mcpCopyAccessToken")
                    mcpTryPrompt
                }
                Text("Use a local extension, rather than Claude’s remote connector URL field: cloud connections cannot reach this Mac-only server.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Claude local extension guide", destination: URL(string: "https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop")!)
            }
            if let message = mcpSetupMessage {
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .accessibilityIdentifier("mcpSetupMessage")
            }
        }
    }

    private var mcpTryPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask your agent").font(.caption.bold()).foregroundStyle(Color.themePrimaryAccent)
            Text("Search my Jotley notes for release planning and tell me who owns each action.")
                .font(.callout).textSelection(.enabled)
            Button(mcpCopiedItem == "question" ? "Copied ✓" : "Copy request") {
                copyMCP("Search my Jotley notes for release planning and tell me who owns each action.", item: "question")
            }.disabled(!mcp.enabled)
            if mcp.allowsWriting {
                Text("Then try: “Find that note, rename it Launch checklist, and rewrite its summary as a checklist. Keep the transcript unchanged.” Open it in Jotley to see the saved change.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Jotley’s Last agent seen and Last successful request above confirm actual client activity.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func mcpCopyField(_ label: String, value: String, item: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption.bold())
                Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Spacer()
            Button(mcpCopiedItem == item ? "Copied ✓" : "Copy \(label)") { copyMCP(value, item: item) }
                .disabled(!mcp.enabled)
        }
    }

    private func runMCPSetup(_ operation: () throws -> String?) {
        do { mcpSetupMessage = try operation() }
        catch { mcpSetupMessage = "Setup could not finish. \(error.localizedDescription)" }
    }

    private func openMCPClient(_ bundleID: String, name: String) {
        if !JotleyMCPDesktopSetup.openClient(bundleID) {
            // The unified desktop app can register the ChatGPT bundle instead.
            if bundleID == "com.openai.codex", JotleyMCPDesktopSetup.openClient("com.openai.chat") { return }
            mcpSetupMessage = "\(name) could not be found. Open it from Applications after installing it."
        }
    }
}
