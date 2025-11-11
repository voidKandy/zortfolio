const std = @import("std");
const log = std.log.scoped(.Router);
const tls = @import("tls");
const Request = std.http.Server.Request;
const Connection = std.net.Server.Connection;

const MAX_BUF = 1024;

/// https://cookbook.ziglang.cc/05-03-http-server-std/
pub fn main() !void {
    const addr = try std.net.Address.parseIp("127.0.0.1", 3000);
    var server = try std.net.Address.listen(addr, .{ .reuse_address = true });
    defer server.deinit();

    log.info("Start HTTP server at {f}", .{addr});

    while (true) {
        const conn = server.accept() catch |err| {
            log.err("failed to accept connection: {s}", .{@errorName(err)});
            continue;
        };
        var gpa = std.heap.GeneralPurposeAllocator(.{
            .thread_safe = true,
        }){};
        const allocator = gpa.allocator();
        _ = std.Thread.spawn(.{}, acceptConnection, .{ allocator, conn }) catch |err| {
            log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
            conn.stream.close();
            continue;
        };
    }
}

fn acceptConnection(a: std.mem.Allocator, conn: Connection) !void {
    defer conn.stream.close();

    log.info("Got new client({f})!", .{conn.address});
    var auth = try tls.config.CertKeyPair.fromFilePath(a, std.fs.cwd(), "local_ssl/localhost.crt", "local_ssl/localhost.key");
    defer auth.deinit(a);

    var tls_conn = tls.serverFromStream(conn.stream, .{
        .auth = &auth,
    }) catch |err| {
        log.err(
            \\ TLS Failed: {any}
        , .{err});
        return err;
    };
    var recv_buffer: [2048 * 2048]u8 = undefined;
    var send_buffer: [2048]u8 = undefined;
    var connection_br = tls_conn.reader(&recv_buffer);
    var connection_bw = tls_conn.writer(&send_buffer);
    var server = std.http.Server.init(&connection_br.interface, &connection_bw.interface);
    while (server.reader.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return err,
        };

        switch (request.upgradeRequested()) {
            .other => |other_protocol| {
                log.err("Not supported protocol, {s}", .{other_protocol});
                return;
            },
            .websocket => |key| {
                var ws = try request.respondWebSocket(.{ .key = key orelse "" });
                try serveWebSocket(&ws);
            },
            .none => {
                try serveHTTP(a, &server, &request);
            },
        }
    }
}
fn serveHTTP(a: std.mem.Allocator, server: *std.http.Server, request: *Request) !void {
    log.warn("serving...", .{});
    var body: ?[]u8 = null;
    defer if (body) |b| a.free(b);

    if (request.head.content_length) |content_len| {
        log.warn("reading content len: {d}\n", .{content_len});
        const buf = a.alloc(u8, content_len) catch @panic("out of memory");
        var reader = server.reader.bodyReader(buf, request.head.transfer_encoding, content_len);
        body = try reader.readAlloc(a, content_len);
        log.info("Received body: {s}", .{body.?});
    }

    switch (request.head.method) {
        .POST => {},
        .GET => {},
        .HEAD, .PUT, .DELETE, .CONNECT, .OPTIONS, .TRACE, .PATCH => {},
    }

    try request.respond(
        "Hello World from Zig HTTP server",
        .{
            .extra_headers = &.{
                .{ .name = "custom-header", .value = "custom value" },
            },
        },
    );
}

fn serveWebSocket(ws: *std.http.Server.WebSocket) !void {
    try ws.writeMessage("Hello from Zig WebSocket server", .text);
    while (true) {
        const msg = try ws.readSmallMessage();
        if (msg.opcode == .connection_close) {
            log.info("Client closed the WebSocket", .{});
            return;
        }
        try ws.writeMessage(msg.data, msg.opcode);
    }
}
