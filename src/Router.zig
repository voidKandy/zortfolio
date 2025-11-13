const std = @import("std");
const log = std.log.scoped(.Router);
const zemplate = @import("zemplate");
const http = @import("http.zig");

const Request = std.http.Server.Request;
const BufferedWriter = @import("BufferedWriter.zig");

pub const StatelessFunc =
    *const fn (r: Request, writer: *std.Io.Writer) anyerror!void;

pub const StatefulFunc = *fn (*const anyopaque, Request, *std.Io.Writer) anyerror!void;

const RouteFunc = union(enum) {
    stateless: StatelessFunc,
    stateful: struct {
        state_ptr: usize,
        func_ptr: usize,
    },

    fn call(self: @This(), request: Request, writer: *BufferedWriter) anyerror!void {
        switch (self) {
            .stateful => |b| try @call(.auto, @as(StatefulFunc, @ptrFromInt(b.func_ptr)), .{ @as(*anyopaque, @ptrFromInt(b.state_ptr)), request, &writer.interface }),
            .stateless => |f| try f(request, &writer.interface),
        }
    }
};

const RoutesMap = std.StringHashMap(RouteFunc);
const Self = @This();

map: RoutesMap,
notFound: RouteFunc = .{ .stateless = &struct {
    fn handle(r: Request, w: *std.Io.Writer) anyerror!void {
        _ = r;
        try w.writeAll("<div><h1>404 NOT FOUND</h1></div>");
    }
}.handle },

pub fn init(a: std.mem.Allocator) Self {
    Components.init(a);
    return .{
        .map = RoutesMap.init(a),
    };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
}

pub fn clone(self: *Self) !Self {
    const map = try self.map.clone();
    return .{ .map = map };
}

pub fn dispatch(self: *Self, a: std.mem.Allocator, request: *Request) !void {
    var writer = try BufferedWriter.init(a);
    defer writer.deinit(a);

    const needs_hydration = http.getHeader(request.*, "hx-request") == null;

    var not_found = false;

    if (self.map.get(request.head.target)) |func| {
        try func.call(request.*, &writer);
    } else {
        not_found = true;
        try self.notFound.call(request.*, &writer);
    }

    if (needs_hydration) {
        var component_buffer = try std.ArrayList(u8).initCapacity(a, 1024);
        try Components.tryUpdate(a);
        var iter = Components.get().map.iterator();
        while (iter.next()) |entry| {
            const info = entry.value_ptr.*;
            try component_buffer.appendSlice(a, info.content);
        }
        var tmplt = HydrationTemplate.init(.{
            .hydration = try writer.buffer.toOwnedSlice(a),
            .components = try component_buffer.toOwnedSlice(a),
        }, a);

        var render = try tmplt.render();
        try writer.interface.writeAll(try render.toOwnedSlice(a));
    }

    try request.respond(writer.buffer.items, .{
        .status = if (not_found) .not_found else .ok,
    });
}

inline fn checkStatefulHandlerRegisterArgs(func: anytype) void {
    comptime {
        const func_info = @typeInfo(@TypeOf(func));

        // Need to check:
        // 1) func is function pointer
        const f = blk: {
            if (func_info == .pointer) {
                const inner = @typeInfo(func_info.pointer.child);
                if (inner == .@"fn") {
                    break :blk inner.@"fn";
                }
            }
            @compileError("Expected func to be a function pointer. Found " ++
                @typeName(@TypeOf(func)));
        };

        // 2) snd arg is Request
        if (f.params.len != 3) {
            @compileError("Expected func to have three parameters");
        }
        const arg_2_type = f.params[1].type.?;
        if (arg_2_type != Request) {
            @compileError("Expected func's second argument to be of type Request. Found " ++
                @typeName(arg_2_type));
        }

        const arg_3_type = f.params[2].type.?;
        if (arg_3_type != *std.Io.Writer) {
            @compileError("Expected func's second argument to be of type *std.Io.Writer. Found " ++
                @typeName(arg_3_type));
        }

        if (!ret: {
            const ret_info = @typeInfo(f.return_type orelse break :ret false);
            const set = ret_info.error_union.error_set;
            const payload = ret_info.error_union.payload;

            break :ret (payload == void and set == anyerror);
        }) {
            @compileError("Expected func's return type to be anyerror!void. Found " ++
                @typeName(f.return_type.?));
        }
    }
}

pub fn registerStatelessHandler(self: *Self, path: []const u8, func: StatelessFunc) !void {
    if (self.map.contains(path)) {
        return error.AlreadyExists;
    }

    return self.map.put(path, .{ .stateless = func });
}

/// Ripped from zap router
/// https://github.com/zigzap/zap/blob/master/src/router.zig#L147
pub fn registerStatefulHandler(self: *Self, path: []const u8, instance: *anyopaque, func: anytype) !void {
    checkStatefulHandlerRegisterArgs(func);
    if (path.len == 0) {
        return error.EmptyPath;
    }

    if (self.map.contains(path)) {
        return error.AlreadyExists;
    }

    try self.map.put(path, RouteFunc{ .stateful = .{
        .state_ptr = @intFromPtr(instance),
        .func_ptr = @intFromPtr(func),
    } });
}

pub fn registerStatelessNotFoundHandler(self: *Self, func: StatelessFunc) !void {
    self.notFound = .{ .stateless = func };
}

pub fn registerStatefulNotFoundHandler(self: *Self, instance: *anyopaque, func: anytype) !void {
    checkStatefulHandlerRegisterArgs(func);
    self.notFound = .{ .stateful = .{
        .state_ptr = @intFromPtr(instance),
        .func_ptr = @intFromPtr(func),
    } };
}

const HydrationTemplateInfo = struct {
    hydration: []u8,
    components: []u8,
};

const HydrationTemplate = zemplate.Template(HydrationTemplateInfo, @embedFile("pages/index.html"));

const Components = struct {
    const COMPONENTS_DIR = "components";
    /// Components' Info mapped by their names hashed
    map: std.AutoHashMap(u64, Info),
    mrc: std.atomic.Value(i128),
    should_update: std.atomic.Value(bool),

    var singleton: @This() = undefined;
    var default_required_component_keys: std.AutoHashMap(u64, void) = undefined;
    pub fn init(a: std.mem.Allocator) void {
        singleton = .{
            .map = readComponents(a, COMPONENTS_DIR) catch @panic("failed to init components singleton"),
            .mrc = std.atomic.Value(i128).init(computeMRC(COMPONENTS_DIR) catch @panic("failed to get mrc")),
            .should_update = std.atomic.Value(bool).init(false),
        };

        const thread = std.Thread.spawn(.{}, backgroundWatcher, .{ &singleton.mrc, &singleton.should_update }) catch @panic("failed to spawn watcher thread");
        thread.detach();
    }
    /// Background thread function
    fn backgroundWatcher(mrc_ptr: *std.atomic.Value(i128), update_ptr: *std.atomic.Value(bool)) void {
        while (true) {
            std.Thread.sleep(5_000_000_000); // sleep 5 seconds (nano)
            const new_mrc = computeMRC(COMPONENTS_DIR) catch continue;
            if (new_mrc > mrc_ptr.load(.seq_cst)) {
                mrc_ptr.store(new_mrc, .seq_cst);
                update_ptr.store(true, .seq_cst);
            }
        }
    }

    pub fn get() @This() {
        return singleton;
    }

    pub fn tryUpdate(a: std.mem.Allocator) !void {
        if (singleton.should_update.swap(false, .seq_cst)) {
            singleton.map.deinit();
            singleton.map = readComponents(a, COMPONENTS_DIR) catch return error.UpdateFailed;
        }
    }

    fn computeMRC(parent_path: []const u8) !i128 {
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(parent_path, .{ .iterate = true });

        var latest: i128 = 0;
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            const stat = try dir.statFile(entry.name);
            const modified = @as(i128, @intCast(stat.mtime));
            if (modified > latest) latest = modified;
        }
        return latest;
    }

    fn readComponents(a: std.mem.Allocator, parent_path: []const u8) !std.AutoHashMap(u64, Info) {
        log.warn("reading components\n", .{});
        var map = std.AutoHashMap(u64, Info).init(a);
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(parent_path, .{ .iterate = true });
        var iter = dir.iterate();

        while (try iter.next()) |f| {
            if (f.kind != .file) {
                continue;
            }

            const info = try Info.new(f.name, a);
            try map.put(std.hash_map.hashString(info.name), info);
        }

        return map;
    }

    const Info = struct {
        path: []u8,
        content: []u8,
        name: []u8,

        fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.content);
            allocator.free(self.path);
        }

        fn new(path: []const u8, allocator: std.mem.Allocator) !@This() {
            var split = std.mem.splitBackwardsScalar(u8, path, '.');

            if (!std.mem.eql(u8, split.first(), "html")) {
                return error.NotHTML;
            }
            const filename = split.next() orelse return error.InvalidFilename;

            var uppercase_idcs: []usize = try allocator.alloc(usize, filename.len);
            var len: usize = 0;
            for (filename, 0..) |ch, i| {
                if (std.ascii.isUpper(ch)) {
                    uppercase_idcs[len] = i;
                    len += 1;
                }
            }
            const component_name: []u8 = try allocator.alloc(u8, filename.len + len);

            var i: usize = 0;
            for (filename) |ch| {
                if (std.ascii.isUpper(ch)) {
                    component_name[i] = '-';
                    i += 1;
                    component_name[i] = std.ascii.toLower(ch);
                } else {
                    component_name[i] = ch;
                }
                i += 1;
            }

            const fullpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ COMPONENTS_DIR, path });
            const file = try std.fs.cwd().openFile(fullpath, .{});
            defer file.close();
            const content = try file.readToEndAlloc(allocator, 8092);

            return @This(){ .path = fullpath, .name = component_name, .content = content };
        }
    };
};
