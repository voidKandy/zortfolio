const std = @import("std");
const log = std.log.scoped(.http);
const tls = @import("tls");
const mime = @import("mime");
const FileServer = @import("FileServer.zig");
const Request = std.http.Server.Request;
const Connection = std.net.Server.Connection;

const Router = struct {
    const RoutesMap = std.StringHashMap(*const fn (r: *Request, writer: std.Io.Writer) anyerror!void);
    // const FileMap = std.(*const fn (r: *Request, writer: std.Io.Writer) anyerror!void);
    routes: RoutesMap,
    files: FileServer,
    allocator: std.mem.Allocator,
    tls_auth: ?*tls.config.CertKeyPair = null,
    server: std.net.Server = undefined,

    const Self = @This();

    pub fn init(
        a: std.mem.Allocator,
        dir: std.fs.Dir,
    ) Self {
        return .{
            .files = FileServer.init(.{
                .allocator = a,
                .root_dir = dir,
            }) catch @panic("failed to init file server"),
            .routes = RoutesMap.init(a),
            .allocator = a,
        };
    }

    pub fn withTls(self: *Self, dir: std.fs.Dir, cert_path: []const u8, key_path: []const u8) !void {
        const auth = self.allocator.create(tls.config.CertKeyPair) catch @panic("out of memory");
        auth.* = try tls.config.CertKeyPair.fromFilePath(self.allocator, dir, cert_path, key_path);
        self.tls_auth = auth;
    }

    pub fn deinit(self: *Self) void {
        self.routes.deinit();
        if (self.tls_auth) |a| {
            a.deinit(self.allocator);
            self.allocator.destroy(a);
        }
        self.server.deinit();
    }

    pub fn startServer(self: *Self, addr: std.net.Address, opts: std.net.Address.ListenOptions) !void {
        log.info(
            \\ Listening on {f}
        , .{addr});
        self.server = try std.net.Address.listen(addr, opts);
    }

    pub fn listen(self: *Self) !void {
        while (true) {
            var conn = self.server.accept() catch |err| {
                log.err(
                    \\ Failed to accept connection: {s}
                , .{@errorName(err)});
                continue;
            };

            log.info(
                \\ Connected to client at address: {f}
                \\
            , .{conn.address});

            // var server = try secureConnection(self.tls_auth.?, conn);
            _ = std.Thread.spawn(.{}, handleConnection, .{
                self.allocator,
                conn,
                self.tls_auth,
            }) catch |err| {
                log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
                conn.stream.close();
                continue;
            };
        }
    }
};

const ConnectionContext = struct {};

fn handleConnection(a: std.mem.Allocator, conn: std.net.Server.Connection, auth: ?*tls.config.CertKeyPair) !void {
    var tls_conn: ?*tls.Connection = null;
    defer {
        conn.stream.close();
        if (tls_conn) |c| c.close() catch |e| {
            log.err(
                \\ Failed to close TLS connection: {any}
            , .{e});
        };
    }

    const recv_buf = try a.alloc(u8, 16 * 1024);
    const send_buf = try a.alloc(u8, 16 * 1024);
    defer a.free(recv_buf);
    defer a.free(send_buf);

    var server: std.http.Server = undefined;

    if (auth) |auth_ptr| {
        var tls_c = try tls.serverFromStream(conn.stream, .{ .auth = auth_ptr });
        tls_conn = &tls_c;

        var r = tls_conn.?.reader(recv_buf);
        var w = tls_conn.?.writer(send_buf);
        server = std.http.Server.init(&r.interface, &w.interface);
        log.warn(
            \\ Created HTTPS connection
        , .{});
    } else {
        var r = conn.stream.reader(recv_buf);
        var w = conn.stream.writer(send_buf);
        server = std.http.Server.init(r.interface(), &w.interface);
        log.warn(
            \\ Created HTTP connection
        , .{});
    }

    while (true) {
        switch (server.reader.state) {
            .ready => {
                var req = server.receiveHead() catch |err| switch (err) {
                    error.HttpConnectionClosing => break,
                    else => {
                        log.err("receiveHead err: {any}", .{err});
                        break;
                    },
                };

                switch (req.upgradeRequested()) {
                    .other => |other_protocol| {
                        log.err("Not supported protocol, {s}", .{other_protocol});
                        return;
                    },
                    .websocket => |key| {
                        var ws = try req.respondWebSocket(.{ .key = key orelse "" });
                        try serveWebSocket(&ws);
                    },
                    .none => {
                        try serveHTTP(a, &server, &req);
                    },
                }
            },
            .closing => break,
            else => {},
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

/// https://cookbook.ziglang.cc/05-03-http-server-std/
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();
    var router = Router.init(allocator, try std.fs.cwd().openDir("serve", .{ .iterate = true }));
    // try router.withTls(std.fs.cwd(), "local_ssl/localhost.crt", "local_ssl/localhost.key");
    const addr = try std.net.Address.parseIp("0.0.0.0", 3000);
    try router.startServer(addr, .{ .reuse_address = true });
    defer router.deinit();

    try router.listen();
}
