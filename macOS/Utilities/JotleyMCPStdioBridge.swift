import Foundation
import MCP

/// The agent launches the existing app executable in this mode. It does not
/// instantiate SwiftUI, open Core Data or enable access. Only the running app
/// accesses the library and enforces permission/revision checks.
enum JotleyMCPStdioBridge {
    static func run() async {
        do {
            let connection = try configuration()
            try await forward(endpoint: connection.endpoint, token: connection.token)
        } catch {
            // Never include requests, note content or credentials in diagnostics.
            FileHandle.standardError.write(Data("Open Jotley, enable MCP access in Settings → Integrations → MCP, and restart this server in your agent. If macOS asks, approve Jotley’s existing Keychain access.\n".utf8))
            exit(1)
        }
    }

    private static func configuration() throws -> (endpoint: URL, token: String) {
        #if DEBUG
        // Integration harness only; these overrides are absent from Release.
        if let address = ProcessInfo.processInfo.environment["JOTLEY_MCP_TEST_ENDPOINT"],
           let token = ProcessInfo.processInfo.environment["JOTLEY_MCP_TEST_TOKEN"],
           let endpoint = URL(string: address), endpoint.scheme == "http", endpoint.host == "127.0.0.1",
           endpoint.path == "/mcp", token.count == 64 {
            return (endpoint, token)
        }
        #endif
        guard let token = try JotleyMCPToken.loadExisting() else {
            throw LocalError.message("Enable MCP in Jotley first.")
        }
        return (URL(string: "http://127.0.0.1:\(JotleyMCPService.defaultPort)/mcp")!, token)
    }

    static func forward(endpoint: URL, token: String) async throws {
        let client = Client(name: "Jotley desktop bridge", version: "1.0.0")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 660
        let transport = HTTPClientTransport(endpoint: endpoint, configuration: configuration, streaming: false, requestModifier: { request in
            var request = request
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        })
        do {
            let upstream = try await client.connect(transport: transport)
            let server = Server(name: "Jotley", version: "1.0.0", instructions: upstream.instructions, capabilities: .init(tools: .init()))
            await server.withMethodHandler(ListTools.self) { parameters in
                let context = try await client.send(ListTools.request(parameters))
                return try await context.value
            }
            await server.withMethodHandler(CallTool.self) { parameters in
                let context = try await client.send(CallTool.request(parameters))
                return try await context.value
            }
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
            await server.stop()
            await client.disconnect()
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
