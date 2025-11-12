const std = @import("std");
const log = std.log.scoped(.http);
const tls = @import("tls");
const mime = @import("mime");

const FileServer = @import("FileServer.zig");
const BufferedWriter = @import("BufferedWriter.zig");
const Request = std.http.Server.Request;
const Connection = std.net.Server.Connection;

const RoutesMap = std.StringHashMap(*const fn (r: *Request, writer: std.Io.Writer) anyerror!void);

const Router = struct {
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

            var gpa = std.heap.GeneralPurposeAllocator(.{
                .thread_safe = true,
            }){};
            var ctx = try ConnectionContext.init(
                gpa.allocator(),
                &self,
                conn,
            );

            errdefer ctx.deinit();

            _ = std.Thread.spawn(.{}, ConnectionContext.handleConnection, .{
                &ctx,
            }) catch |err| {
                log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
                conn.stream.close();
                continue;
            };
        }
    }
};

const ConnectionType = union(enum) {
    http: std.net.Server.Connection,
    https: *tls.Connection,
};

/// Data associated with a connection to a single client
const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    recv_buf: []u8,
    send_buf: []u8,
    connection: std.net.Server.Connection,
    tls: ?*tls.Connection = null,
    auth: *const ?*tls.config.CertKeyPair,
    file_server: FileServer,
    routes: RoutesMap,

    const Self = @This();
    const RECV_BUF_SIZE = 16 * 1024;
    const SEND_BUF_SIZE = 16 * 1024;

    fn init(a: std.mem.Allocator, router: *const *Router, conn: std.net.Server.Connection) std.mem.Allocator.Error!Self {
        return .{
            .allocator = a,
            .connection = conn,
            .file_server = try router.*.files.clone(a),
            .routes = try router.*.routes.clone(),
            .auth = &router.*.tls_auth,
            .recv_buf = try a.alloc(u8, RECV_BUF_SIZE),
            .send_buf = try a.alloc(u8, SEND_BUF_SIZE),
        };
    }

    fn deinit(self: *Self) void {
        self.file_server.deinit(self.allocator);
        self.routes.deinit();

        self.connection.stream.close();
        if (self.tls) |conn| {
            conn.close() catch |e| {
                log.err(
                    \\ Failed to close TLS connection: {any}
                , .{e});
            };
            self.allocator.destroy(conn);
        }

        self.allocator.free(self.recv_buf);
        self.allocator.free(self.send_buf);
    }

    fn handleConnection(self: *Self) !void {
        var server: std.http.Server = undefined;
        defer self.deinit();

        if (self.auth.*) |auth_ptr| {
            const tls_conn = try self.allocator.create(tls.Connection);
            tls_conn.* = try tls.serverFromStream(self.connection.stream, .{ .auth = auth_ptr });
            self.tls = tls_conn;

            var r = self.tls.?.reader(self.recv_buf);
            var w = self.tls.?.writer(self.send_buf);
            server = std.http.Server.init(&r.interface, &w.interface);
            log.warn(
                \\ Created HTTPS connection
            , .{});
        } else {
            var r = self.connection.stream.reader(self.recv_buf);
            var w = self.connection.stream.writer(self.send_buf);
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
                            try self.serveHTTP(&server, &req);
                        },
                    }
                },
                .closing => break,
                else => {},
            }
        }
    }

    fn serveHTTP(self: *Self, server: *std.http.Server, request: *Request) !void {
        var body: ?[]u8 = null;
        defer if (body) |b| self.allocator.free(b);

        if (self.file_server.serve(request)) |_| {
            return;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => {
                log.err(
                    \\ File server encountered an error: {any}
                , .{err});
                return err;
            },
        }

        if (request.head.content_length) |content_len| {
            log.warn("reading content len: {d}\n", .{content_len});
            const buf = self.allocator.alloc(u8, content_len) catch @panic("out of memory");
            var reader = server.reader.bodyReader(buf, request.head.transfer_encoding, content_len);
            body = try reader.readAlloc(self.allocator, content_len);
            log.info("Received body: {s}", .{body.?});
        }
        log.info(
            \\ PATH: {s}
        , .{request.head.target});

        if (self.routes.get(request.head.target)) |func| {
            const writer = try BufferedWriter.init(self.allocator);
            try func(request, writer.interface);
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
};

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

    try router.withTls(std.fs.cwd(), "local_ssl/localhost.crt", "local_ssl/localhost.key");
    const addr = try std.net.Address.parseIp("0.0.0.0", 3000);
    try router.startServer(addr, .{ .reuse_address = true });
    defer router.deinit();

    try router.listen();
}
