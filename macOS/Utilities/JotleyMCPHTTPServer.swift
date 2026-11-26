import Foundation
import MCP
import NIOCore
import NIOHTTP1
import NIOPosix

/// NIO supplies bounded HTTP parsing; the official MCP SDK handles JSON-RPC.
final class JotleyMCPHTTPServer {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    func start(port: Int, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) async throws -> Int {
        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 32)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: false).flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(IdleStateHandler(readTimeout: .seconds(10)))
                    try channel.pipeline.syncOperations.addHandler(JotleyMCPHTTPHandler(handler: handler))
                }
            }
            .bind(host: "127.0.0.1", port: port).get()
        self.channel = channel
        return channel.localAddress?.port ?? port
    }

    func stop() async {
        try? await channel?.close().get()
        channel = nil
        try? await group.shutdownGracefully()
    }
}

private final class JotleyMCPHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var head: HTTPRequestHead?
    private var body = Data()
    private var processing = false

    init(handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) { self.handler = handler }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !processing else { return }
        switch unwrapInboundIn(data) {
        case .head(let head):
            guard head.headers.count <= 64 else { reject(context, code: 431); return }
            // Ambiguous duplicate security headers are rejected before conversion to a dictionary.
            for name in ["host", "authorization", "origin", "content-type", "mcp-protocol-version"] {
                guard head.headers[name].count <= 1 else { reject(context, code: 400); return }
            }
            self.head = head
        case .body(var buffer):
            guard body.count + buffer.readableBytes <= 1048576 else { reject(context, code: 413); return }
            if let bytes = buffer.readBytes(length: buffer.readableBytes) { body.append(contentsOf: bytes) }
        case .end:
            guard let head else { reject(context, code: 400); return }
            processing = true
            let request = HTTPRequest(method: head.method.rawValue,
                headers: Dictionary(head.headers.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first }),
                body: body, path: head.uri)
            let channel = context.channel
            Task {
                let response = await handler(request)
                Self.write(response, to: channel)
            }
        }
    }

    private func reject(_ context: ChannelHandlerContext, code: Int) {
        processing = true
        Self.write(.error(statusCode: code, .invalidRequest("Request rejected")), to: context.channel)
    }

    private static func write(_ response: HTTPResponse, to channel: Channel) {
        channel.eventLoop.execute {
            let data = response.bodyData ?? Data()
            var headers = HTTPHeaders(response.headers.map { ($0.key, $0.value) })
            headers.replaceOrAdd(name: "Content-Length", value: "\(data.count)")
            headers.replaceOrAdd(name: "Connection", value: "close")
            headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
            channel.write(HTTPServerResponsePart.head(.init(version: .http1_1,
                status: .init(statusCode: response.statusCode), headers: headers)), promise: nil)
            if !data.isEmpty {
                var buffer = channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
            }
            channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in channel.close(promise: nil) }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent { context.close(promise: nil) }
        else { context.fireUserInboundEventTriggered(event) }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
