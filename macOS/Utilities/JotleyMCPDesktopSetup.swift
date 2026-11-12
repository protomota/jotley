import AppKit
import Foundation
import UniformTypeIdentifiers

/// Setup is an explicit user action. Never edits a personal client on launch.
@MainActor
enum JotleyMCPDesktopSetup {
    static var command: String { Bundle.main.executableURL?.path ?? "" }
    static let argument = "--mcp-stdio"
    static var projectConfiguration: String? {
        guard !command.isEmpty, let data = try? JSONSerialization.data(withJSONObject: ["mcpServers": ["jotley": [
            "type": "stdio", "command": command, "args": [argument]
        ]]], options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
    enum SetupError: LocalizedError {
        case invalidConfiguration, unsafeFile, changedFile, missingResources, exportFailed
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "The existing .mcp.json is not a valid MCP configuration. It was left unchanged."
            case .unsafeFile: return "Choose a project with a regular .mcp.json file, rather than a link or directory."
            case .changedFile: return "The project configuration changed during setup. Try saving again."
            case .missingResources: return "The Claude extension is missing from this Jotley build."
            case .exportFailed: return "The Claude extension could not be saved. Choose another location and try again."
            }
        }
    }

    nonisolated static func mergedProjectConfiguration(existing: Data?, connection: Data) throws -> (data: Data, replacesConnection: Bool) {
        guard let incoming = try JSONSerialization.jsonObject(with: connection) as? [String: Any],
              let entries = incoming["mcpServers"] as? [String: Any], let jotley = entries["jotley"] else {
            throw SetupError.invalidConfiguration
        }
        var root: [String: Any] = [:]
        if let existing {
            guard let parsed = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw SetupError.invalidConfiguration
            }
            root = parsed
        }
        if let servers = root["mcpServers"], !(servers is [String: Any]) { throw SetupError.invalidConfiguration }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        let replaces = servers["jotley"].map { !NSDictionary(dictionary: ["entry": $0]).isEqual(to: ["entry": jotley]) } ?? false
        servers["jotley"] = jotley
        root["mcpServers"] = servers
        return (try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]), replaces)
    }

    static func saveProject(configuration: String) throws -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose your Claude Code project"
        panel.message = "Jotley will add its bundled connection to .mcp.json in this folder. Other servers are preserved. No Jotley access token is saved in this file."
        panel.prompt = "Save connection"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return nil }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(".mcp.json")
        let existing = try readConfiguration(file)
        let merged = try mergedProjectConfiguration(existing: existing, connection: Data(configuration.utf8))
        if merged.replacesConnection {
            let alert = NSAlert()
            alert.messageText = "Replace this project’s Jotley connection?"
            alert.informativeText = "This updates only the jotley entry to use this copy of Jotley. Other MCP servers and project settings are preserved."
            alert.addButton(withTitle: "Replace Jotley connection")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        }
        let temporary = folder.appendingPathComponent(".jotley-mcp-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: merged.data, attributes: [.posixPermissions: 0o600]) else {
            throw SetupError.exportFailed
        }
        guard try readConfiguration(file) == existing else { throw SetupError.changedFile }
        if existing != nil {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: temporary, to: file)
        }
        return "Connection saved for \(folder.lastPathComponent). Open that folder in Claude’s Code tab and start a new local session. Keep this copy of Jotley in its current location."
    }

    private static func readConfiguration(_ file: URL) throws -> Data? {
        // fileExists follows links, so check the link itself first (including broken links).
        if let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
           values.isSymbolicLink == true || values.isDirectory == true { throw SetupError.unsafeFile }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    static func saveClaudeExtension(endpoint: String) throws -> String? {
        guard let resources = Bundle.main.url(forResource: "JotleyClaudeMCP", withExtension: nil) else { throw SetupError.missingResources }
        let panel = NSSavePanel()
        panel.title = "Save Claude chat extension"
        panel.nameFieldStringValue = "Jotley.mcpb"
        panel.allowedContentTypes = [UTType(filenameExtension: "mcpb") ?? .data]
        panel.message = "Install this file in Claude’s local extensions, then paste the access token from Jotley. The extension file contains no access token."
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: resources.appendingPathComponent("server.js"), to: staging.appendingPathComponent("server.js"))
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("manifest.json"))) as? [String: Any] ?? [:]
        var server = manifest["server"] as? [String: Any] ?? [:]
        var config = server["mcp_config"] as? [String: Any] ?? [:]
        var environment = config["env"] as? [String: String] ?? [:]
        environment["JOTLEY_MCP_URL"] = endpoint
        config["env"] = environment; server["mcp_config"] = config; manifest["server"] = server
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: staging.appendingPathComponent("manifest.json"))
        if let tiff = NSApplication.shared.applicationIconImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: staging.appendingPathComponent("icon.png"))
        } else { throw SetupError.missingResources }
        let archive = staging.appendingPathExtension("mcpb")
        defer { try? FileManager.default.removeItem(at: archive) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", staging.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SetupError.exportFailed }
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        return "Jotley.mcpb saved. Install it in Claude’s Extensions settings, then paste your Jotley access token."
    }

    static func openClient(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }
}
