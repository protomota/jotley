import AppKit
import SwiftUI

extension SettingsView {
    var mcpView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(Color.themePrimaryAccent)
                        .frame(width: 52, height: 52)
                        .background(Color.themePrimaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connect your AI agents").font(.title2.bold())
                        Text("Work with your notes from Claude Code, Codex or Claude chat on your Mac. Set up directly in the desktop apps.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(get: { mcp.enabled }, set: { value in
                        mcpCopiedItem = nil
                        Task { await mcp.setEnabled(value) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable MCP access").font(.headline)
                            Text("Only on this Mac · You control what agents can do").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(mcp.isChanging)
                    .accessibilityIdentifier("mcpEnableToggle")
                    Picker("Note access", selection: Binding(get: { mcp.allowsWriting }, set: { mcp.setAllowsWriting($0) })) {
                        Text("Read only").tag(false)
                        Text("Read & write").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("mcpNoteAccess")
                    Text(mcp.allowsWriting
                         ? "Edit, organize, summarize, copy and delete notes. Manage tags, folders and Custom Words."
                         : "Agents can read notes, tags, folders and Custom Words. Choose Read & write to allow changes.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack(spacing: 8) {
                        Circle().fill(mcp.enabled ? Color.green : Color.secondary).frame(width: 7, height: 7)
                        Text(mcp.enabled ? "Server ready" : mcp.status)
                        if mcp.isChanging { ProgressView().controlSize(.small) }
                        Spacer()
                        Button(mcp.isTesting ? "Checking…" : "Test connection") { Task { await mcp.testConnection() } }
                            .disabled(!mcp.enabled || mcp.isChanging || mcp.isTesting)
                            .accessibilityIdentifier("mcpTestConnection")
                    }.font(.callout).accessibilityIdentifier("mcpConnectionStatus")
                    if let result = mcp.testMessage {
                        Text(result).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("mcpTestResult")
                    }
                    if let name = mcp.lastClientName, let date = mcp.lastClientDate {
                        Label {
                            Text("Last agent seen: \(name) · \(date.formatted(date: .omitted, time: .shortened))")
                        } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        .font(.caption).accessibilityIdentifier("mcpLastAgent")
                    } else {
                        Text(mcp.enabled ? "Waiting for your agent. A server check does not connect your agent." : "Turn access on to begin setup.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let tool = mcp.lastToolName {
                        Text("Last successful request: \(tool) · \(mcp.requestCount) this session")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("mcpLastTool")
                    }
                }
                .padding(18).background(Color.themePrimaryAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.themePrimaryAccent.opacity(0.14), lineWidth: 1))

                if let error = mcp.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Need a hand?").font(.headline)
                    Text("Get personal help with MCP setup or another Jotley issue. One ticket opens a private conversation with Brad.").font(.callout).foregroundStyle(.secondary)
                    JotleyTechnicalSupportButton()
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.themePrimaryAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

                mcpDesktopSetup

                Label("Connected agents can read your library and may send retrieved text to their AI provider. Read & write also allows changes and permanent deletion. Keep Jotley open while using MCP.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                DisclosureGroup("Advanced: other clients & access controls", isExpanded: $mcpShowingDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(mcp.endpoint).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Text("The HTTP configuration contains a private access token. Jotley stores its original in Keychain. Desktop bridge setup does not include it in copied fields or project files.")
                        Button(mcpCopiedItem == "configuration" ? "Configuration copied ✓" : "Copy HTTP configuration") {
                            copyMCP(mcp.clientConfiguration, item: "configuration")
                        }.disabled(!mcp.enabled).accessibilityIdentifier("mcpCopyClientConfiguration")
                        HStack {
                            Button("Rotate access token") {
                                mcpCopiedItem = nil
                                Task { await mcp.rotateToken() }
                            }.disabled(mcp.isChanging || !mcp.enabled).accessibilityIdentifier("mcpRotateToken")
                            Link("Claude Code setup guide", destination: URL(string: "https://code.claude.com/docs/en/mcp")!)
                        }
                        Text("Rotation revokes old credentials. Restart the Jotley server in Claude Code or Codex afterward; the bundled bridge reads the new token from Keychain. For Claude chat, replace the extension token. Update direct HTTP clients with fresh configuration. Turning access off or quitting Jotley stops access.")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                }.font(.callout)
            }.padding(28)
        }
    }

    func mcpSetupStep<Content: View>(_ number: Int, title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(.caption, design: .rounded).bold())
                .foregroundStyle(Color.themePrimaryAccent).frame(width: 25, height: 25)
                .background(Color.themePrimaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.callout.bold())
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func copyMCP(_ value: String?, item: String) {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(value, forType: .string) { mcpCopiedItem = item }
    }
}
