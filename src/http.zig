const std = @import("std");
const log = std.log.scoped(.http);
const tls = @import("tls");
const mime = @import("mime");

const FileServer = @import("FileServer.zig");
const Router = @import("Router.zig");
const BufferedWriter = @import("BufferedWriter.zig");
const Request = std.http.Server.Request;
const Connection = std.net.Server.Connection;

pub fn getHeader(r: Request, key: []const u8) ?[]const u8 {
    var iter = r.iterateHeaders();

    while (iter.next()) |h| {
        if (std.ascii.eqlIgnoreCase(key, h.name)) {
            return h.value;
        }
    }

    return null;
}

pub fn parse(r: *const Request) struct { path: []const u8, query: ?[]const u8 } {
    const target = r.head.target;
    if (std.mem.indexOfScalar(u8, target, '?')) |i| {
        return .{
            .path = target[0..i],
            .query = target[i + 1 ..],
        };
    } else {
        return .{
            .path = target,
            .query = null,
        };
    }
}

pub const Dispatcher = struct {
    router: Router,
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
            .router = Router.init(a),
            .allocator = a,
        };
    }

    pub fn withTls(self: *Self, dir: std.fs.Dir, cert_path: []const u8, key_path: []const u8) !void {
        const auth = self.allocator.create(tls.config.CertKeyPair) catch @panic("out of memory");
        auth.* = try tls.config.CertKeyPair.fromFilePath(self.allocator, dir, cert_path, key_path);
        self.tls_auth = auth;
    }

    pub fn deinit(self: *Self) void {
        self.router.deinit(self.allocator);
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
        var gpa = std.heap.GeneralPurposeAllocator(.{
            .thread_safe = true,
        }){};
        defer if (gpa.detectLeaks()) log.err("LEAKS DETECTED IN CONNECTION THREAD ALLOCATOR\n", .{});

        while (true) {
            var conn = self.server.accept() catch |err| {
                log.err(
                    \\ Failed to accept connection: {s}
                , .{@errorName(err)});
                continue;
            };
            errdefer conn.stream.close();

            log.info(
                \\ Connected to client at address: {f}
                \\
            , .{conn.address});

            const ctx = self.allocator.create(ConnectionContext) catch @panic("out of memory");
            ctx.* = try ConnectionContext.init(
                gpa.allocator(),
                &self,
                conn,
            );

            const thread = std.Thread.spawn(.{}, ConnectionContext.handleConnection, .{
                ctx,
            }) catch |err| {
                log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
                ctx.deinit();
                self.allocator.destroy(ctx);
                continue;
            };

            thread.detach();
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
    connection: ConnectionType,
    auth: *const ?*tls.config.CertKeyPair,
    file_server: FileServer,
    router: Router,

    const Self = @This();
    const RECV_BUF_SIZE = 16 * 1024;
    const SEND_BUF_SIZE = 16 * 1024;

    fn init(a: std.mem.Allocator, dispatcher: *const *Dispatcher, conn: std.net.Server.Connection) std.mem.Allocator.Error!Self {
        return .{
            .allocator = a,
            .connection = .{ .http = conn },
            .file_server = try dispatcher.*.files.clone(a),
            .router = try dispatcher.*.router.clone(),
            .auth = &dispatcher.*.tls_auth,
            .recv_buf = try a.alloc(u8, RECV_BUF_SIZE),
            .send_buf = try a.alloc(u8, SEND_BUF_SIZE),
        };
    }

    fn deinit(self: *Self) void {
        switch (self.connection) {
            .http => |c| c.stream.close(),
            .https => |c| {
                c.close() catch |e| {
                    log.err(
                        \\ Failed to close TLS connection: {any}
                    , .{e});
                };
                self.allocator.destroy(c);
            },
        }

        self.auth = undefined;
        self.allocator.free(self.recv_buf);
        self.allocator.free(self.send_buf);
        self.file_server.deinit(self.allocator);
        self.router.deinit(self.allocator);
    }

    fn handleConnection(self: *Self) !void {
        var server: std.http.Server = undefined;
        defer self.deinit();

        if (self.auth.*) |auth_ptr| {
            const tls_conn = try self.allocator.create(tls.Connection);
            tls_conn.* = try tls.serverFromStream(self.connection.http.stream, .{ .auth = auth_ptr });
            self.connection = .{ .https = tls_conn };

            var r = self.connection.https.reader(self.recv_buf);
            var w = self.connection.https.writer(self.send_buf);
            server = std.http.Server.init(&r.interface, &w.interface);
            log.info(
                \\ Created HTTPS connection
            , .{});
        } else {
            var r = self.connection.http.stream.reader(self.recv_buf);
            var w = self.connection.http.stream.writer(self.send_buf);
            server = std.http.Server.init(r.interface(), &w.interface);
            log.info(
                \\ Created HTTP connection
            , .{});
        }
        while (true) {
            switch (server.reader.state) {
                .ready => {
                    var req = server.receiveHead() catch |err| switch (err) {
                        error.HttpConnectionClosing => {
                            log.warn(
                                \\ Closing Connection
                            , .{});
                            break;
                        },
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
                .closing => {
                    log.warn(
                        \\ Connection Closed
                    , .{});
                    break;
                },

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

        try self.router.dispatch(self.allocator, request);
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
