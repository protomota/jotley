import AppKit
import CoreData
import Foundation
import MCP
import SwiftUI
@testable import Jotley

#if !JOTLEY_MCP_DEMO
@main
#endif
struct MCPIntegration {
    @MainActor static func main() {
        Task { @MainActor in
            do {
                try await checks()
                print("PASS: Jotley MCP integration checks")
                exit(0)
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    @MainActor static func fixture() throws -> SharedPersistenceController {
        let store = try SharedPersistenceController(inMemory: true)
        let note = try store.create(title: "Release planning", text: "Maya owns the onboarding review on Friday. Alex will test accessibility. Ship after both checks pass.",
                                    id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        note.setValue("Maya: onboarding review Friday. Alex: accessibility checks. Release follows approval.", forKey: "summary")
        note.setValue("Follow up with Maya on Thursday.", forKey: "notes")
        let tag = NSEntityDescription.insertNewObject(forEntityName: "Tag", into: store.context)
        tag.setValue(UUID(), forKey: "id"); tag.setValue("launch", forKey: "name")
        note.mutableSetValue(forKey: "tags").add(tag)
        let garden = try store.create(title: "Garden ideas", text: "Plant basil and rosemary in the sunny corner.")
        garden.setValue(Date().addingTimeInterval(-86400), forKey: "timestamp")
        try store.save()
        return store
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "MCPIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func text(_ content: [Tool.Content]) -> String {
        content.compactMap { if case .text(let value, _, _) = $0 { return value }; return nil }.joined(separator: "\n")
    }

    static func connect(endpoint: String, token: String) async throws -> Client {
        let client = Client(name: "Jotley integration client", version: "1.0", configuration: .strict)
        let transport = HTTPClientTransport(endpoint: URL(string: endpoint)!, streaming: false, requestModifier: { request in
            var request = request
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        })
        _ = try await client.connect(transport: transport)
        return client
    }

    static func request(endpoint: String, token: String?, headers: [String: String] = [:], method: String = "POST", body: String = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}") async throws -> Int {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if method == "POST" { request.httpBody = Data(body.utf8) }
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as! HTTPURLResponse).statusCode
    }

    @MainActor private static func customWordChecks(client: Client, service: JotleyMCPService, defaults: UserDefaults) async throws {
        defaults.set("PulseCanvas", forKey: CustomSpeechWords.defaultsKey)
        let listed = try await client.callTool(name: "list_custom_words", arguments: [:])
        let state = try JSONSerialization.jsonObject(with: Data(text(listed.content).utf8)) as! [String: Any]
        try expect(state["words"] as? [String] == ["PulseCanvas"], "MCP did not read the Settings preference")
        let patch: [String: Value] = ["expected_revision": .string(state["revision"] as! String), "add": ["Textley", "pulsecanvas"]]
        let denied = try await client.callTool(name: "update_custom_words", arguments: patch)
        try expect(denied.isError == true, "Read-only MCP allowed a Custom Words change")
        service.setAllowsWriting(true)
        defer { service.setAllowsWriting(false) }
        let applied = try await client.callTool(name: "update_custom_words", arguments: patch)
        try expect(applied.isError != true && CustomSpeechWords.saved(in: defaults) == ["PulseCanvas", "Textley"], "MCP failed to save to the Settings preference")
        let stale = try await client.callTool(name: "update_custom_words", arguments: patch)
        try expect(stale.isError == true, "MCP accepted a stale word-list revision")
        let revised = try JSONSerialization.jsonObject(with: Data(text(applied.content).utf8)) as! [String: Any]
        let removed = try await client.callTool(name: "update_custom_words", arguments: ["expected_revision": .string(revised["revision"] as! String), "remove": ["pulsecanvas"]])
        try expect(removed.isError != true && CustomSpeechWords.saved(in: defaults) == ["Textley"], "MCP failed to remove only the requested word")
        print("PASS: Custom Words shares the Settings preference, checks revisions and respects Read only")
    }

    @MainActor static func checks() async throws {
        try desktopConfigurationChecks()
        try checklistChecks()
        let store = try fixture()
        let suite = "JotleyMCPTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let token = String(repeating: "a", count: 64) // Synthetic test credential, never a real client token.
        let service = JotleyMCPService(defaults: defaults, port: 0, token: token)
        await service.attach(store: store)
        try expect(!service.enabled && !service.allowsWriting, "MCP must default to off and read only")
        await service.setEnabled(true)
        try expect(service.enabled, service.errorMessage ?? "Server did not start")
        let endpoint = service.endpoint
        try expect(URL(string: endpoint)?.host == "127.0.0.1", "Server must bind to loopback")

        let missing = try await request(endpoint: endpoint, token: nil)
        let wrong = try await request(endpoint: endpoint, token: "wrong")
        let origin = try await request(endpoint: endpoint, token: token, headers: ["Origin": "https://example.com"])
        let host = try await request(endpoint: endpoint, token: token, headers: ["Host": "attacker.example"])
        let invalidVersion = try await request(endpoint: endpoint, token: token, headers: ["MCP-Protocol-Version": "1900-01-01"])
        let get = try await request(endpoint: endpoint, token: token, method: "GET")
        let malformed = try await request(endpoint: endpoint, token: token, body: "not json")
        let oversized = try await request(endpoint: endpoint, token: token, body: String(repeating: "x", count: 1048577))
        try expect(missing == 401 && wrong == 401, "Unauthenticated access was accepted")
        try expect(origin == 403 && host == 403, "Browser/DNS rebinding guards failed")
        try expect(invalidVersion == 400 && get == 405 && malformed == 400 && oversized == 413, "HTTP validation failed")
        print("PASS: authentication, Origin/Host, protocol version, methods, malformed and oversized bodies")

        let client = try await connect(endpoint: endpoint, token: token)
        try expect(service.lastClientName == "Jotley integration client", "The real client handshake was not shown")
        await service.testConnection()
        try expect(service.testMessage?.contains("passed") == true, "The built-in connection test failed")
        try expect(service.lastClientName == "Jotley integration client", "Self-test replaced the real agent indicator")
        let tools = try await client.listTools().tools
        try expect(Set(tools.map(\.name)) == ["list_notes", "search_notes", "read_note", "create_note", "update_note", "replace_note_text", "duplicate_note", "delete_note", "list_tags", "create_tag", "update_tag", "delete_tag", "list_folders", "create_folder", "update_folder", "delete_folder", "set_note_tags", "move_note", "list_summary_templates", "generate_note_summary", "create_summary_template", "update_summary_template", "delete_summary_template", "list_custom_words", "update_custom_words"], "Unexpected tools")
        try expect(tools.filter { $0.annotations.readOnlyHint == true }.count == 7, "Read-only annotations missing")
        try expect(tools.first { $0.name == "delete_note" }?.annotations.destructiveHint == true, "Deletion must be marked destructive")
        let listed = try await client.callTool(name: "list_notes", arguments: ["limit": 1])
        let listedJSON = try JSONSerialization.jsonObject(with: Data(text(listed.content).utf8)) as! [String: Any]
        try expect((listedJSON["notes"] as? [Any])?.count == 1 && listedJSON["next_offset"] as? Int == 1, "List pagination failed")
        let searched = try await client.callTool(name: "search_notes", arguments: ["query": "Maya"])
        try expect(text(searched.content).contains("Release planning") && !text(searched.content).contains("Garden ideas"), "Text search failed")
        let tagged = try await client.callTool(name: "search_notes", arguments: ["query": "launch"])
        try expect(text(tagged.content).contains("Release planning"), "Tag search failed")
        let noteID: Value = "11111111-1111-4111-8111-111111111111"
        let read = try await client.callTool(name: "read_note", arguments: ["id": noteID])
        try expect(text(read.content).contains("onboarding review") && text(read.content).contains("Follow up with Maya"), "Full note retrieval failed")
        try expect(service.lastToolName == "read_note" && service.lastToolDate != nil, "Successful reads were not reported in Settings")
        let chunk = try await client.callTool(name: "read_note", arguments: ["id": noteID, "section": "transcript", "offset": 5, "limit": 10])
        let chunkJSON = try JSONSerialization.jsonObject(with: Data(text(chunk.content).utf8)) as! [String: Any]
        try expect(chunkJSON["content"] as? String == "owns the o" && chunkJSON["next_offset"] as? Int == 15, "Transcript chunking failed")
        for arguments: [String: Value] in [["id": "bad"], ["id": noteID, "section": "audio"], ["id": noteID, "limit": -1], ["id": noteID, "limit": 1.5], ["id": noteID, "unknown": true]] {
            let result = try await client.callTool(name: "read_note", arguments: arguments)
            try expect(result.isError == true, "Invalid arguments were accepted")
        }
        let unknown = try await client.callTool(name: "delete_note", arguments: ["id": noteID])
        let remainingNotes = try store.notes().count
        try expect(unknown.isError == true && remainingNotes == 2, "A write tool changed the library")
        print("PASS: SDK initialization, discovery, metadata pagination, text/tag search, chunked reads and invalid arguments")

        try await customWordChecks(client: client, service: service, defaults: defaults)
        if ProcessInfo.processInfo.environment["JOTLEY_BRIDGE_CHECK"] != nil {
            try await desktopBridgeCheck(endpoint: endpoint, token: token, writing: false)
            try await desktopBridgeCheck(endpoint: endpoint, token: token, writing: false, native: true)
            service.setAllowsWriting(true)
            try await desktopBridgeCheck(endpoint: endpoint, token: token, writing: true)
            try await desktopBridgeCheck(endpoint: endpoint, token: token, writing: true, native: true)
            service.setAllowsWriting(false)
        }
        try await writeChecks(client: client, service: service, store: store, noteID: noteID)
        try await organizationChecks(client: client, service: service, store: store)

        let second = try await connect(endpoint: endpoint, token: token)
        async let firstCall = client.callTool(name: "search_notes", arguments: ["query": "Maya"])
        async let secondCall = second.callTool(name: "search_notes", arguments: ["query": "basil"])
        let parallel = try await (firstCall, secondCall)
        try expect(text(parallel.0.content).contains("Release planning") && text(parallel.1.content).contains("Garden ideas"), "Concurrent clients crossed responses")
        await client.disconnect(); await second.disconnect()

        await service.rotateToken()
        let revoked = try await request(endpoint: service.endpoint, token: token)
        try expect(service.enabled && revoked == 401, "Rotated credential was still accepted")
        await service.setEnabled(false, persistPreference: false)
        try expect(defaults.bool(forKey: JotleyMCPService.enabledKey), "App shutdown lost the enabled preference")
        await service.setEnabled(false)
        try expect(!service.enabled && !defaults.bool(forKey: JotleyMCPService.enabledKey), "Disable did not persist")
        do {
            _ = try await request(endpoint: service.endpoint, token: token)
            throw NSError(domain: "MCPIntegration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Disabled listener still accepted requests"])
        } catch let error as NSError where error.domain == NSURLErrorDomain { }
        print("PASS: concurrent clients, token revocation, shutdown preference and disabled listener")

        if CommandLine.arguments.contains("--content-only") {
            print("PASS: authenticated MCP content, organization and template checks; Keychain persistence check not requested")
            return
        }
        // Exercise the production Keychain path under the harness's separate identity.
        func configuredToken(_ service: JotleyMCPService) throws -> String {
            guard let config = service.clientConfiguration,
                  let json = try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any],
                  let servers = json["mcpServers"] as? [String: [String: Any]],
                  let headers = servers["jotley"]?["headers"] as? [String: String],
                  let header = headers["Authorization"], header.hasPrefix("Bearer ") else {
                throw LocalError.message("Copied client configuration is invalid")
            }
            return String(header.dropFirst(7))
        }
        let reusablePort = URL(string: endpoint)!.port!
        let persisted = JotleyMCPService(defaults: defaults, port: reusablePort)
        await persisted.attach(store: store)
        await persisted.setEnabled(true)
        try expect(persisted.enabled, persisted.errorMessage ?? "Keychain-backed server did not start")
        let savedToken = try configuredToken(persisted)
        persisted.setAllowsWriting(true)
        let savedClient = try await connect(endpoint: persisted.endpoint, token: savedToken)
        _ = try await savedClient.listTools()
        await savedClient.disconnect()
        await persisted.setEnabled(false, persistPreference: false)
        let relaunched = JotleyMCPService(defaults: defaults, port: reusablePort)
        await relaunched.attach(store: store)
        let restoredToken = try configuredToken(relaunched)
        try expect(savedToken == restoredToken && relaunched.enabled && relaunched.allowsWriting, "Token, enable or access preference did not survive service recreation")
        await relaunched.rotateToken()
        let rotatedToken = try configuredToken(relaunched)
        let revokedSaved = try await request(endpoint: relaunched.endpoint, token: savedToken)
        let validNew = try await request(endpoint: relaunched.endpoint, token: rotatedToken)
        try expect(savedToken != rotatedToken && revokedSaved == 401 && validNew == 200, "Keychain rotation did not revoke old access")
        await relaunched.setEnabled(false)
        print("PASS: sandbox Keychain generation, copied configuration, restored enable preference and persisted rotation")
    }

    static func desktopConfigurationChecks() throws {
        let incoming = Data(#"{"mcpServers":{"jotley":{"type":"http","url":"http://127.0.0.1:17321/mcp","headers":{"Authorization":"Bearer test"}}}}"#.utf8)
        let existing = Data(#"{"keep":"value","mcpServers":{"other":{"command":"other"},"jotley":{"url":"old"}}}"#.utf8)
        let merged = try JotleyMCPDesktopSetup.mergedProjectConfiguration(existing: existing, connection: incoming)
        let root = try JSONSerialization.jsonObject(with: merged.data) as! [String: Any]
        let servers = root["mcpServers"] as! [String: Any]
        try expect(root["keep"] as? String == "value" && servers["other"] != nil && merged.replacesConnection, "Project merge lost settings or did not identify replacement")
        let unchanged = try JotleyMCPDesktopSetup.mergedProjectConfiguration(existing: merged.data, connection: incoming)
        try expect(!unchanged.replacesConnection && unchanged.data == merged.data, "Identical setup was not idempotent")
        let new = try JotleyMCPDesktopSetup.mergedProjectConfiguration(existing: nil, connection: incoming)
        try expect(!new.replacesConnection, "New configuration requires replacement")
        for source in ["[]", "not json", "{\"mcpServers\":[]}"] {
            do {
                _ = try JotleyMCPDesktopSetup.mergedProjectConfiguration(existing: Data(source.utf8), connection: incoming)
                throw LocalError.message("Invalid configuration was accepted")
            } catch is JotleyMCPDesktopSetup.SetupError { }
            catch let error as NSError where error.domain == NSCocoaErrorDomain { }
        }
        print("PASS: desktop project merge preserves other entries, detects replacement and rejects invalid files")
    }

    @MainActor static func desktopBridgeCheck(endpoint: String, token: String, writing: Bool, native: Bool = false) async throws {
        guard let script = Bundle.main.url(forResource: "mcp-desktop-bridge-check", withExtension: "cjs"),
              let bridge = Bundle.main.url(forResource: "JotleyClaudeMCP", withExtension: nil)?.appendingPathComponent("server.js") else {
            throw LocalError.message("Desktop bridge test resources are missing")
        }
        let process = Process()
        guard let node = ProcessInfo.processInfo.environment["JOTLEY_NODE_BINARY"] else {
            throw LocalError.message("Set JOTLEY_NODE_BINARY to the Node executable used for bridge verification")
        }
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["JOTLEY_MCP_URL"] = endpoint
        environment["JOTLEY_MCP_TOKEN"] = token
        environment["JOTLEY_BRIDGE_SCRIPT"] = bridge.path
        environment["JOTLEY_BRIDGE_WRITE"] = writing ? "1" : "0"
        if native {
            environment["JOTLEY_NATIVE_BRIDGE_BINARY"] = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/JotleyBridge").path
            environment["JOTLEY_MCP_TEST_ENDPOINT"] = endpoint
            environment["JOTLEY_MCP_TEST_TOKEN"] = token
        }
        process.environment = environment
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        try expect(status == 0, "Desktop extension bridge verification failed")
    }

    @MainActor static func checklistChecks() throws {
        let source = "- [ ] **Maya**: Review onboarding.\n  + [x] 📝 **Alex**: Test accessibility.\n* [X] Ship.\n1. [ ] Follow up.\n- [Guide](https://example.com)\n- [Maya] is a literal label.\n- `[ ]` is code."
        let lines = ParsedNoteMarkdown.rendering(source).lines
        try expect(lines.prefix(4).map(\.taskState) == [.unchecked, .checked, .checked, .unchecked], "Task-list state was not parsed")
        try expect(String(lines[0].text.characters) == "Maya: Review onboarding." && lines[1].indentation == 2 && String(lines[1].text.characters).hasPrefix("📝 Alex:"), "Task markers leaked or Unicode/inline formatting was lost")
        try expect(lines.dropFirst(4).allSatisfy { $0.taskState == nil } && String(lines[5].text.characters).hasPrefix("[Maya]"), "Literal brackets or links became tasks")
        try expect("- [ ] Maya: Review.\n- [X] Alex: Test.".previewSnippet() == "Maya: Review. Alex: Test.", "Sidebar preview leaked task brackets")
        for heading in ["", "## Action Items\n", "## Key Points\n"] {
            let summary = StructuredSummary(ParsedNoteMarkdown.rendering(heading + "- [ ] Maya: Review.\n- [x] Alex: Test."))
            let items = (summary.overview?.items ?? []) + summary.sections.flatMap(\.items)
            try expect(items.map(\.taskState) == [.unchecked, .checked] && items[0].label.map { String($0.characters) } == "Maya", "Structured summary dropped checkbox state or owner label")
        }
        for tail in ["- [", "- [x", "- [ ]", "- [X]"] {
            try expect(ParsedNoteMarkdown.rendering(tail, isStreaming: true).lines.allSatisfy { $0.text.characters.isEmpty }, "Incomplete streamed task marker was exposed")
        }
        print("PASS: Markdown tasks render checked/unchecked state without raw brackets; previews, owner labels, nesting, Unicode and literal brackets preserved")
    }

    @MainActor static func organizationChecks(client: Client, service: JotleyMCPService, store: SharedPersistenceController) async throws {
        func json(_ result: (content: [Tool.Content], isError: Bool?)) throws -> [String: Any] {
            try expect(result.isError != true, "Organization tool failed: \(text(result.content))")
            return try JSONSerialization.jsonObject(with: Data(text(result.content).utf8)) as! [String: Any]
        }
        func read(_ id: Value) async throws -> [String: Any] { try json(await client.callTool(name: "read_note", arguments: ["id": id])) }
        func revision(_ id: Value) async throws -> Value { .string(try await read(id)["revision"] as! String) }
        let fake: Value = "11111111-1111-4111-8111-111111111111"
        for name in ["create_tag", "update_tag", "delete_tag", "create_folder", "update_folder", "delete_folder", "set_note_tags", "move_note", "generate_note_summary"] {
            var arguments: [String: Value] = ["id": fake, "expected_revision": "unused"]
            if name.hasPrefix("create_") { arguments = ["name": "Denied"] }
            if name == "update_tag" { arguments["name"] = "Denied" }
            if name == "set_note_tags" { arguments["tag_ids"] = [] }
            if name == "move_note" { arguments["folder_id"] = .null }
            if name == "generate_note_summary" { arguments["template"] = .string(LocalSummaryTemplate.auto.key) }
            let denied = try await client.callTool(name: name, arguments: arguments)
            try expect(denied.isError == true && text(denied.content).contains("read only"), "Read only allowed \(name)")
        }
        service.setAllowsWriting(true)
        let created = try json(await client.callTool(name: "create_note", arguments: ["title": "Organization fixture", "transcript": "Maya will review the launch.", "summary": "Original summary"]))
        let id = Value.string(created["id"] as! String)
        let tag = try json(await client.callTool(name: "create_tag", arguments: ["name": "Release Review"]))
        let tagID = Value.string(tag["id"] as! String)
        let same = try json(await client.callTool(name: "create_tag", arguments: ["name": "release-review"]))
        try expect(same["id"] as? String == tag["id"] as? String, "Equivalent tag names duplicated")
        let folder = try json(await client.callTool(name: "create_folder", arguments: ["name": "Launches"]))
        let folderID = Value.string(folder["id"] as! String)
        _ = try json(await client.callTool(name: "set_note_tags", arguments: ["id": id, "expected_revision": try await revision(id), "tag_ids": .array([tagID])]))
        let moved = try json(await client.callTool(name: "move_note", arguments: ["id": id, "expected_revision": try await revision(id), "folder_id": folderID]))
        try expect(moved["folder"] as? String == "Launches" && moved["tags"] as? [String] == ["Release-Review"], "Membership assignment failed")
        let filtered = try json(await client.callTool(name: "search_notes", arguments: ["query": "Maya", "folder_id": folderID, "tag_id": tagID]))
        try expect((filtered["notes"] as? [[String: Any]])?.count == 1, "Combined folder/tag filtering failed")
        func libraryItem(_ name: String, id: Value) async throws -> [String: Any] {
            let result = try json(await client.callTool(name: "list_" + name, arguments: [:]))
            return (result[name] as! [[String: Any]]).first { $0["id"] as? String == id.stringValue }!
        }
        let currentTag = try await libraryItem("tags", id: tagID)
        let oldRevision = try await revision(id)
        _ = try json(await client.callTool(name: "update_tag", arguments: ["id": tagID, "expected_revision": .string(currentTag["revision"] as! String), "name": "Launch Ready"]))
        let changedRevision = try await revision(id)
        try expect(changedRevision != oldRevision, "Global tag rename did not invalidate the note revision")
        let stale = try await client.callTool(name: "move_note", arguments: ["id": id, "expected_revision": oldRevision, "folder_id": .null])
        try expect(stale.isError == true, "Stale organization edit accepted")
        let currentFolder = try await libraryItem("folders", id: folderID)
        _ = try json(await client.callTool(name: "update_folder", arguments: ["id": folderID, "expected_revision": .string(currentFolder["revision"] as! String), "name": "Launch work", "sort_order": 3]))
        let note = try store.notes().first { $0.localNoteID?.uuidString == id.stringValue }!
        let operation = store.beginNoteOperation(for: note.objectID)
        let busyTag = try await libraryItem("tags", id: tagID)
        let blocked = try await client.callTool(name: "delete_tag", arguments: ["id": tagID, "expected_revision": .string(busyTag["revision"] as! String)])
        try expect(blocked.isError == true, "Deleting a tag changed an actively generated note")
        store.endNoteOperation(lease: operation)
        let templates = try json(await client.callTool(name: "list_summary_templates", arguments: [:]))
        try expect((templates["templates"] as? [[String: Any]])?.count == LocalSummaryTemplate.allCases.count, "Native summary templates missing")
        let custom = try json(await client.callTool(name: "create_summary_template", arguments: ["name": "MCP fixture \(UUID())", "instructions": "Only include decisions and action items."]))
        let templateID = Value.string(custom["id"] as! String)
        let templateRevision = Value.string(custom["revision"] as! String)
        let templateKey = Value.string(custom["key"] as! String)
        service.setAllowsWriting(false)
        let readonlyTemplate = try await client.callTool(name: "delete_summary_template", arguments: ["id": templateID, "expected_revision": templateRevision])
        try expect(readonlyTemplate.isError == true, "Read-only MCP deleted a template")
        service.setAllowsWriting(true)
        let editedTemplate = try json(await client.callTool(name: "update_summary_template", arguments: ["id": templateID, "expected_revision": templateRevision, "name": "Edited \(UUID())", "instructions": "Use Next Steps with owners and dates."]))
        let staleTemplate = try await client.callTool(name: "delete_summary_template", arguments: ["id": templateID, "expected_revision": templateRevision])
        try expect(staleTemplate.isError == true, "Stale template deletion was accepted")
        JotleyMCPTools.summaryGeneratorForTesting = { _, template, _ in
            try expect(template.key == templateKey.stringValue && template.prompt == "Use Next Steps with owners and dates.", "Custom template instructions did not reach native generation")
            return "## Next Steps\n- Review launch."
        }
        _ = try json(await client.callTool(name: "generate_note_summary", arguments: ["id": id, "expected_revision": try await revision(id), "template": templateKey]))
        try expect(note.text("summaryType") == templateKey.stringValue, "Custom template key was not saved")
        _ = try json(await client.callTool(name: "delete_summary_template", arguments: ["id": templateID, "expected_revision": .string(editedTemplate["revision"] as! String)]))
        try expect(note.text("summary") == "## Next Steps\n- Review launch.", "Deleting a template modified a saved summary")
        let missingTemplate = try await client.callTool(name: "generate_note_summary", arguments: ["id": id, "expected_revision": try await revision(id), "template": templateKey])
        try expect(missingTemplate.isError == true, "Deleted template silently fell back to Auto")
        print("PASS: custom template MCP CRUD, read-only enforcement, revision conflicts, native generation and summary-preserving deletion")
        JotleyMCPTools.summaryGeneratorForTesting = { _, _, _ in "- [ ] Review launch." }
        defer { JotleyMCPTools.summaryGeneratorForTesting = nil }
        let generated = try json(await client.callTool(name: "generate_note_summary", arguments: ["id": id, "expected_revision": try await revision(id), "template": .string(LocalSummaryTemplate.auto.key)]))
        try expect(generated["title"] as? String == "Organization fixture" && note.text("summary") == "- [ ] Review launch." && note.text("transcription") == "Maya will review the launch.", "Native summary generation changed unrelated fields")
        JotleyMCPTools.summaryGeneratorForTesting = { _, _, _ in
            service.setAllowsWriting(false)
            return "Must not save"
        }
        let revoked = try await client.callTool(name: "generate_note_summary", arguments: ["id": id, "expected_revision": try await revision(id), "template": .string(LocalSummaryTemplate.auto.key)])
        try expect(revoked.isError == true && note.text("summary") == "- [ ] Review launch.", "Permission revocation during native generation still wrote content")
        service.setAllowsWriting(true)
        let finalFolder = try await libraryItem("folders", id: folderID)
        _ = try json(await client.callTool(name: "delete_folder", arguments: ["id": folderID, "expected_revision": .string(finalFolder["revision"] as! String)]))
        let finalTag = try await libraryItem("tags", id: tagID)
        _ = try json(await client.callTool(name: "delete_tag", arguments: ["id": tagID, "expected_revision": .string(finalTag["revision"] as! String)]))
        let preserved = try await read(id)
        try expect(preserved["folder"] as? String == "" && (preserved["tags"] as? [String])?.isEmpty == true && note.text("summary") == "- [ ] Review launch.", "Organization deletion deleted or altered note content")
        _ = try json(await client.callTool(name: "delete_note", arguments: ["id": id, "expected_revision": try await revision(id)]))
        service.setAllowsWriting(false)
        print("PASS: tag/folder CRUD, membership, combined filters, stale revisions, processing protection, native regeneration and in-flight permission revocation; organization deletion preserves notes")
    }

    @MainActor static func writeChecks(client: Client, service: JotleyMCPService, store: SharedPersistenceController, noteID: Value) async throws {
        func json(_ result: (content: [Tool.Content], isError: Bool?)) throws -> [String: Any] {
            try expect(result.isError != true, "Tool failed: \(text(result.content))")
            return try JSONSerialization.jsonObject(with: Data(text(result.content).utf8)) as! [String: Any]
        }
        func read(_ id: Value) async throws -> [String: Any] { try json(await client.callTool(name: "read_note", arguments: ["id": id])) }
        func revision(_ id: Value) async throws -> Value { .string(try await read(id)["revision"] as! String) }
        let initial = try await read(noteID)
        let originalRevision = Value.string(initial["revision"] as! String)
        for name in ["create_note", "update_note", "replace_note_text", "duplicate_note", "delete_note"] {
            let arguments: [String: Value]
            switch name {
            case "create_note": arguments = ["title": "Blocked"]
            case "update_note": arguments = ["id": noteID, "expected_revision": originalRevision, "changes": ["title": "Blocked"]]
            case "replace_note_text": arguments = ["id": noteID, "expected_revision": originalRevision, "field": "summary", "old_text": "Maya", "new_text": "Blocked"]
            default: arguments = ["id": noteID, "expected_revision": originalRevision]
            }
            let denied = try await client.callTool(name: name, arguments: arguments)
            try expect(denied.isError == true && text(denied.content).contains("read only"), "Read-only access allowed \(name)")
        }
        service.setAllowsWriting(true)
        let updated = try json(await client.callTool(name: "update_note", arguments: [
            "id": noteID, "expected_revision": originalRevision, "changes": [
                "title": "Release checklist", "summary": "- Review onboarding\n- Test accessibility",
                "description": "Launch review", "notes": "Meet Thursday", "date": "2026-11-08T10:30:00.123Z",
                "cleaned_transcript": "Clean copy", "source_url": "https://example.com/release", "summary_type": "checklist"
            ]]))
        try expect(updated["title"] as? String == "Release checklist" && updated["date"] as? String == "2026-11-08T10:30:00.123Z", "Title/date update failed")
        try expect(updated["tags"] as? [String] == ["launch"], "Update changed tags")
        let note = try store.notes().first { $0.localNoteID?.uuidString == noteID.stringValue }!
        try expect(note.text("transcription").contains("Maya owns") && note.text("sourceDescription") == "Launch review", "Patch overwrote an unrelated field")
        let stale = try await client.callTool(name: "update_note", arguments: ["id": noteID, "expected_revision": originalRevision, "changes": ["title": "Stale"]])
        try expect(stale.isError == true && text(stale.content).contains("Revision conflict"), "A stale revision overwrote a change")

        for changes: Value in [["title": "Partial", "date": "yesterday"], ["title": "Partial", "summary": 42], ["title": "Partial", "settings": true], [:]] {
            let invalid = try await client.callTool(name: "update_note", arguments: ["id": noteID, "expected_revision": try await revision(noteID), "changes": changes])
            try expect(invalid.isError == true && note.text("title") == "Release checklist", "Invalid changes were partially saved")
        }
        let missingRevision = try await client.callTool(name: "delete_note", arguments: ["id": noteID])
        try expect(missingRevision.isError == true && !note.isDeleted, "Deletion did not require a revision")

        let recording = try store.beginRecording(note)
        let recordingWrite = try await client.callTool(name: "delete_note", arguments: ["id": noteID, "expected_revision": try await revision(noteID)])
        try expect(recordingWrite.isError == true && text(recordingWrite.content).contains("recording"), "MCP deleted an active recording")
        store.endRecording(lease: recording)
        let generationModel = NotesListViewModel(viewContext: store.context, recorder: ProcessTapRecorder(), persistenceController: store)
        generationModel.beginSummaryGeneration(for: note.objectID)
        let generationWrite = try await client.callTool(name: "update_note", arguments: ["id": noteID, "expected_revision": try await revision(noteID), "changes": ["summary": "Unsafe"]])
        try expect(generationWrite.isError == true && text(generationWrite.content).contains("generating"), "MCP raced generation")
        generationModel.endSummaryGeneration(for: note.objectID)

        // Exercise a native editor's conflict check against an MCP write.
        let nativeNote = note as! Note
        let oldSummary = nativeNote.summary ?? ""
        let replaced = try json(await client.callTool(name: "replace_note_text", arguments: ["id": noteID, "expected_revision": try await revision(noteID), "field": "summary", "old_text": "Review onboarding", "new_text": "Approve onboarding"]))
        try expect(replaced["revision"] as? String != updated["revision"] as? String, "Revision did not change")
        do {
            try nativeNote.saveEditedSummary("Old editor draft", original: oldSummary, in: store)
            throw LocalError.message("An old native editor draft overwrote MCP content")
        } catch let error as LocalError { try expect(error.localizedDescription.contains("changed while"), error.localizedDescription) }

        _ = try json(await client.callTool(name: "update_note", arguments: ["id": noteID, "expected_revision": try await revision(noteID), "changes": ["transcript": "New transcript. Second sentence."]]))
        try expect(nativeNote.transcriptUtterances.map(\.text).joined(separator: " ").contains("New transcript"), "Transcript timing metadata is stale")

        // A native correction must keep timing, line breaks and metadata after reload.
        let timedNote = try store.create(title: "Timestamp editor fixture", text: "Review the disign. Ship on Friday.") as! Note
        let timed = [TranscriptUtterance(id: "review", text: "Review the disign.", start: 0, end: 4, speaker: 1),
                     TranscriptUtterance(id: "ship", text: "Ship on Friday.", start: 18, end: 22, speaker: 2)]
        try store.saveNoteChanges(timedNote, values: ["transcriptUtterancesJSON": String(decoding: try JSONEncoder().encode(timed), as: UTF8.self)])
        var edit = TranscriptEditDraft(text: timedNote.transcription!, utterances: timedNote.storedTranscriptUtterances)
        edit.segments[0].text = "Review the design.\nKeep our branding."
        try timedNote.saveEditedTranscript(edit, in: store)
        store.context.refresh(timedNote, mergeChanges: false)
        try expect(timedNote.transcription == "Review the design.\nKeep our branding.\n\nShip on Friday.", "Native correction flattened paragraph breaks")
        try expect(timedNote.storedTranscriptUtterances.map(\.start) == [0, 18], "Native correction erased timestamp anchors")
        try expect(timedNote.transcriptUtterances.map(\.timestampLabel) == ["00:00", "00:18"], "Saved bubbles lost timestamps")
        var staleEdit = TranscriptEditDraft(text: timedNote.transcription!, utterances: timedNote.storedTranscriptUtterances)
        staleEdit.segments[1].text = "Stale correction."
        var updatedTiming = timedNote.storedTranscriptUtterances
        updatedTiming[1] = TranscriptUtterance(id: "ship", text: "Ship on Friday.", start: 20, end: 24, speaker: 2)
        try store.saveNoteChanges(timedNote, values: ["transcriptUtterancesJSON": String(decoding: try JSONEncoder().encode(updatedTiming), as: UTF8.self)])
        do {
            try timedNote.saveEditedTranscript(staleEdit, in: store)
            throw LocalError.message("Stale transcript editor overwrote newer timing")
        } catch let error as LocalError { try expect(error.localizedDescription.contains("changed while"), error.localizedDescription) }
        print("PASS: native transcript correction, reload, line breaks, timestamps and timing conflict guard")

        let created = try json(await client.callTool(name: "create_note", arguments: ["title": "Agent draft", "transcript": .string(String(repeating: "Long note. ", count: 10000)), "description": "Created through MCP"]))
        let createdID = Value.string(created["id"] as! String)
        let longRead = try json(await client.callTool(name: "read_note", arguments: ["id": createdID, "section": "transcript", "offset": 100000]))
        try expect(longRead["total_characters"] as? Int == 110000, "Long note failed beyond the old request limit")
        _ = try json(await client.callTool(name: "update_note", arguments: ["id": createdID, "expected_revision": try await revision(createdID), "changes": ["transcript": "aaa"]]))
        let ambiguous = try await client.callTool(name: "replace_note_text", arguments: ["id": createdID, "expected_revision": try await revision(createdID), "field": "transcript", "old_text": "aa", "new_text": "b"])
        let unchanged = try json(await client.callTool(name: "read_note", arguments: ["id": createdID, "section": "transcript"]))
        try expect(ambiguous.isError == true && unchanged["content"] as? String == "aaa", "Overlapping matches were not rejected without changes")
        let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: store.context)
        folder.setValue(UUID(), forKey: "id"); folder.setValue("Work", forKey: "name")
        note.setValue(folder, forKey: "folder")
        try store.save()
        let copy = try json(await client.callTool(name: "duplicate_note", arguments: ["id": noteID, "expected_revision": try await revision(noteID), "title": "Release copy"]))
        let copyID = Value.string(copy["id"] as! String)
        try expect(copyID != noteID && copy["tags"] as? [String] == ["launch"] && copy["folder"] as? String == "Work", "Copy identity/folder/tags failed")
        _ = try json(await client.callTool(name: "update_note", arguments: ["id": copyID, "expected_revision": try await revision(copyID), "changes": ["title": "Independent copy"]]))
        try expect(note.text("title") == "Release checklist", "Editing the copy changed its source")

        for entity in ["NoteChatMessage", "RecordingMarker"] {
            let child = NSEntityDescription.insertNewObject(forEntityName: entity, into: store.context)
            child.setValue(UUID(), forKey: "id"); child.setValue(UUID(uuidString: copyID.stringValue!)!, forKey: "noteId")
        }
        try store.save()
        for id in [createdID, copyID] {
            let deleted = try json(await client.callTool(name: "delete_note", arguments: ["id": id, "expected_revision": try await revision(id)]))
            try expect(deleted["deleted"] as? Bool == true, "Deletion failed")
        }
        for entity in ["NoteChatMessage", "RecordingMarker"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            let count = try store.context.count(for: request)
            try expect(count == 0, "Deletion left orphaned \(entity)")
        }
        service.setAllowsWriting(false)
        let revoked = try await client.callTool(name: "update_note", arguments: ["id": noteID, "expected_revision": try await revision(noteID), "changes": ["title": "Revoked"]])
        try expect(revoked.isError == true, "Permission downgrade did not affect an existing client")
        // Restore search fixtures for subsequent concurrent-client checks.
        try store.saveNoteChanges(note, values: ["title": "Release planning", "transcription": "Maya owns the onboarding review on Friday."])
        print("PASS: read/write permission, atomic edits, dates, stale revisions, active recording/generation, native editor conflicts, long notes, independent copies, deletion and live permission revocation")
    }
}
