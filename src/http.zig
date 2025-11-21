const std = @import("std");
const log = std.log.scoped(.http);
const tls = @import("tls");
const mime = @import("mime");
const zemplate = @import("zemplate");

const FileServer = @import("FileServer.zig");
const Router = @import("Router.zig");
const BufferedWriter = @import("BufferedWriter.zig");
const Request = std.http.Server.Request;
const Connection = std.net.Server.Connection;
const RouteMap = @import("RouteMap.zig");
const ComponentsDirectory = @import("components.zig").ComponentsDirectory;

const HydrationTemplateInfo = struct {
    hydration: []u8,
};

pub const HydrationTemplate = zemplate.Template(HydrationTemplateInfo, @embedFile("index.html"));

pub fn getHeader(r: Request, key: []const u8) ?[]const u8 {
    var iter = r.iterateHeaders();

    while (iter.next()) |h| {
        if (std.ascii.eqlIgnoreCase(key, h.name)) {
            return h.value;
        }
    }

    return null;
}

pub fn parseRequestParts(r: *const Request) struct { path: []const u8, query: ?[]const u8 } {
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

/// Only one instance, spawns ConnectionContexts per connection
pub const Dispatcher = struct {
    routes_map: RouteMap,
    files: FileServer,
    allocator: std.mem.Allocator,
    tls_auth: ?*tls.config.CertKeyPair = null,
    server: std.net.Server = undefined,

    const Self = @This();

    pub fn init(
        a: std.mem.Allocator,
        dir: std.fs.Dir,
    ) Self {
        @import("components.zig").ComponentsDirectory.init(a);
        return .{
            .routes_map = RouteMap.init(a),
            .files = FileServer.init(.{
                .allocator = a,
                .root_dir = dir,
            }) catch @panic("failed to init file server"),
            // .router = Router.init(a),
            .allocator = a,
        };
    }

    pub fn withTls(self: *Self, dir: std.fs.Dir, cert_path: []const u8, key_path: []const u8) !void {
        const auth = self.allocator.create(tls.config.CertKeyPair) catch @panic("out of memory");
        auth.* = try tls.config.CertKeyPair.fromFilePath(self.allocator, dir, cert_path, key_path);
        self.tls_auth = auth;
    }

    pub fn deinit(self: *Self) void {
        @import("components.zig").ComponentsDirectory.deinit();
        self.routes_map.deinit();
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
        const allocator = gpa.allocator();

        while (true) {
            var conn = self.server.accept() catch |err| {
                log.err(
                    \\ Failed to accept connection: {s}
                , .{@errorName(err)});
                continue;
            };
            errdefer conn.stream.close();

            log.warn(
                \\ Connected to client at address: {f}
                \\
            , .{conn.address});

            const ctx = allocator.create(ConnectionContext) catch @panic("out of memory");
            ctx.* = try ConnectionContext.init(
                allocator,
                &self,
                conn,
            );

            const thread = std.Thread.spawn(.{}, ConnectionContext.handleConnection, .{
                ctx,
            }) catch |err| {
                log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
                ctx.deinit();
                allocator.destroy(ctx);
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
    id: i64,
    recv_buf: []u8,
    send_buf: []u8,
    connection: ConnectionType,
    auth: *const ?*tls.config.CertKeyPair,
    file_server: *const FileServer,
    map_ptr: *const @import("RouteMap.zig"),
    const Self = @This();
    const RECV_BUF_SIZE = 16 * 1024;
    const SEND_BUF_SIZE = 16 * 1024;

    var staticid: i64 = 0;
    fn init(allocator: std.mem.Allocator, dispatcher: *const *Dispatcher, conn: std.net.Server.Connection) std.mem.Allocator.Error!Self {
        const myid = staticid;
        staticid += 1;
        return .{
            .allocator = allocator,
            .id = myid,
            .connection = .{ .http = conn },
            .file_server = &dispatcher.*.files,
            .auth = &dispatcher.*.tls_auth,
            .recv_buf = try allocator.alloc(u8, RECV_BUF_SIZE),
            .send_buf = try allocator.alloc(u8, SEND_BUF_SIZE),
            .map_ptr = &dispatcher.*.routes_map,
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
    }

    pub fn dispatchRoutes(self: *Self, request: *Request) !void {
        const is_htmx_request = getHeader(request.*, "hx-request") != null;
        const hydrated_info = getHeader(request.*, "x-hydrated");
        const parts = parseRequestParts(&request.*);

        log.debug(
            \\ is htmx: {any}
            \\ info: {s}
        , .{ is_htmx_request, hydrated_info orelse "null" });

        const oob_swap = if (hydrated_info == null) "innerHTML" else "beforeend";

        var writer = try BufferedWriter.init(self.allocator);
        defer writer.deinit(self.allocator);
        const func_opt = self.map_ptr.*.map.get(parts.path);
        var not_found = func_opt == null;

        if (func_opt) |func|
            func.call(request.*, &writer) catch |e| {
                log.err(
                    \\ Error in route function: {any}
                , .{e});
                not_found = e == error.NotFound;
            };

        if (not_found) {
            try self.map_ptr.*.notFound.call(request.*, &writer);
        }

        if (!is_htmx_request) {
            var tmplt = HydrationTemplate.init(.{
                .hydration = try writer.buffer.toOwnedSlice(self.allocator),
            }, self.allocator);

            var render = try tmplt.render();
            try writer.interface.writeAll(try render.toOwnedSlice(self.allocator));
        }

        const hydration_html = blk: {
            var component_buffer = std.ArrayList(u8).initCapacity(self.allocator, 1024) catch @panic("out of memory");
            component_buffer.appendSlice(self.allocator, std.fmt.allocPrint(self.allocator,
                \\  <section id="components-cache" hx-swap-oob="{s}">
            , .{oob_swap}) catch @panic("out of memory")) catch @panic("out of memory");
            ComponentsDirectory.tryUpdate() catch |e| log.err("Failed to update components directory: {any}\n", .{e});
            var map = try ComponentsDirectory.get().map.clone();

            if (hydrated_info) |header| {
                var header_elems = std.mem.splitScalar(u8, std.mem.trim(u8, header, "\n []"), ',');
                while (header_elems.next()) |elem_name| {
                    const sanitized = std.mem.trim(u8, elem_name, "\n \"");
                    const hash = std.hash_map.hashString(sanitized);
                    log.debug("removing {s} : {d}\n", .{ sanitized, hash });
                    const removed = map.remove(std.hash_map.hashString(sanitized));
                    if (!removed)
                        log.warn("failed to remove {s}\n", .{sanitized});
                }
            }

            var needed_iter = map.valueIterator();
            while (needed_iter.next()) |comp| {
                if (std.mem.indexOf(u8, writer.buffer.items, comp.name) != null) {
                    log.debug("including {s}\n", .{comp.name});
                    try component_buffer.appendSlice(self.allocator, comp.content);
                }
            }

            component_buffer.appendSlice(self.allocator,
                \\  </section>
            ) catch @panic("out of memory");
            break :blk try component_buffer.toOwnedSlice(self.allocator);
        };
        try writer.buffer.appendSlice(self.allocator, hydration_html);

        try request.respond(writer.buffer.items, .{
            .keep_alive = true,
            .status = if (not_found) .not_found else .ok,
        });
    }

    fn handleConnection(self: *Self) !void {
        var server: std.http.Server = undefined;
        defer self.deinit();
        const addr = self.connection.http.address;

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
                                \\ Closing Connection with {f}
                            , .{addr});
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

        if (self.file_server.serve(request)) |_| {
            log.info(
                \\ File server served: {s}
            , .{request.head.target});
            return;
        } else |err| switch (err) {
            error.FileNotFound => {
                log.warn(
                    \\ File server could not find: {s}
                , .{request.head.target});
            },
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

        try self.dispatchRoutes(request);
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
