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
};

const RoutesMap = std.StringHashMap(RouteFunc);
const Self = @This();

map: RoutesMap,
notFound: ?RouteFunc = null,

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

    var component_buffer = try std.ArrayList(u8).initCapacity(a, 1024);
    defer component_buffer.deinit(a);

    const needs_hydration = http.getHeader(request.*, "hx-request") == null;

    var not_found = false;

    if (self.map.get(request.head.target)) |func| {
        switch (func) {
            .stateful => |b| try @call(.auto, @as(StatefulFunc, @ptrFromInt(b.func_ptr)), .{ @as(*anyopaque, @ptrFromInt(b.state_ptr)), request.*, &writer.interface }),
            .stateless => |f| try f(request.*, &writer.interface),
        }

        var keys_iter = Components.get().map.keyIterator();
        while (keys_iter.next()) |key| {
            if (std.mem.indexOf(u8, writer.buffer.items, key.*) != null or Components.default_required_component_keys.get(key.*) != null) {
                log.info("requires component: {s}\n", .{key.*});
                try component_buffer.appendSlice(a, Components.get().map.get(key.*).?.content);
            }
        }
    } else {
        not_found = true;
        if (self.notFound) |func| {
            switch (func) {
                .stateful => |b| try @call(.auto, @as(StatefulFunc, @ptrFromInt(b.func_ptr)), .{ @as(*anyopaque, @ptrFromInt(b.state_ptr)), request.*, &writer.interface }),
                .stateless => |f| try f(request.*, &writer.interface),
            }
        } else {
            try writer.interface.writeAll("<html><body><h1>404 NOT FOUND</h1></body></html>");
        }
    }

    if (needs_hydration) {
        var tmplt = HydrationTemplate.init(.{
            .hydration = writer.buffer.items,
            .components = component_buffer.items,
        }, a);

        var render = try tmplt.render();
        writer.interface.buffer = render.items;
        defer render.deinit(a);
        try request.respond(render.items, .{
            .status = if (not_found) .not_found else .ok,
        });
    } else {
        try writer.interface.writeAll(component_buffer.items);
        try request.respond(writer.buffer.items, .{
            .status = if (not_found) .not_found else .ok,
        });
    }
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

        // 2) snd arg is zap.Request
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

const hydration_template_file =
    @embedFile("pages/index.html");

const HydrationTemplate = zemplate.Template(HydrationTemplateInfo, hydration_template_file);

const Components = struct {
    const COMPONENTS_DIR = "components";
    map: std.StringHashMap(Info),
    // currently we don't do anything with this
    mrc: i128,

    var singleton: @This() = undefined;
    var default_required_component_keys: std.StringHashMap(void) = undefined;
    pub fn init(a: std.mem.Allocator) void {
        singleton = .{
            .map = readComponents(a, COMPONENTS_DIR) catch @panic("failed to init components singleton"),
            .mrc = computeMRC(COMPONENTS_DIR) catch @panic("failed to get mrc"),
        };

        setDefaultReqComponents(a);
    }

    /// don't love this but it prevents a need to parse the index file for needed components everytime
    fn setDefaultReqComponents(a: std.mem.Allocator) void {
        var keys_iter = singleton.map.keyIterator();
        var map = std.StringHashMap(void).init(a);
        var i: usize = 0;
        while (keys_iter.next()) |key| : (i += 1) {
            if (std.mem.indexOf(u8, hydration_template_file, key.*)) |_| {
                log.info(
                    \\ Default includes component {s}
                , .{key.*});
                map.put(key.*, {}) catch @panic("out of memory");
            }
        }
        default_required_component_keys = map;
    }

    pub fn get() @This() {
        return singleton;
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

    fn readComponents(a: std.mem.Allocator, parent_path: []const u8) !std.StringHashMap(Info) {
        log.warn("reading components\n", .{});
        var map = std.StringHashMap(Info).init(a);
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(parent_path, .{ .iterate = true });
        var iter = dir.iterate();

        while (try iter.next()) |f| {
            if (f.kind != .file) {
                continue;
            }

            const info = try Info.new(f.name, a);
            try map.put(info.name, info);
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
