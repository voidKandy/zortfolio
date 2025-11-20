const std = @import("std");
const log = std.log.scoped(.Router);
const zemplate = @import("zemplate");
const http = @import("http.zig");
const ComponentsDirectory = @import("cache.zig").CachedDirectory(ComponentInfo, "components");

const Request = std.http.Server.Request;
const BufferedWriter = @import("BufferedWriter.zig");

pub const ComponentInfo = struct {
    /// Filepath
    path: []u8,
    content: []u8,
    /// Actual name of the HTML component
    name: []u8,
    last_modified: i128,

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.content);
        allocator.free(self.path);
    }

    pub fn fromFile(dir: std.fs.Dir, path: []const u8, allocator: std.mem.Allocator) anyerror!@This() {
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

        const file = try dir.openFile(path, .{});
        const fullpath = try dir.realpathAlloc(allocator, path);
        const last_modified = (try file.stat()).mtime;
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 8092);

        return @This(){
            .path = fullpath,
            .name = component_name,
            .content = content,
            .last_modified = last_modified,
        };
    }
};

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
    ComponentsDirectory.init(a);
    return .{
        .map = RoutesMap.init(a),
    };
}

pub fn deinit(self: *Self, a: std.mem.Allocator) void {
    self.map.deinit();
    ComponentsDirectory.deinit(a);
}

pub fn clone(self: *Self) !Self {
    const map = try self.map.clone();
    return .{ .map = map, .notFound = self.notFound };
}

pub fn dispatch(self: *Self, a: std.mem.Allocator, request: *Request) !void {
    var writer = try BufferedWriter.init(a);
    defer writer.deinit(a);

    const needs_hydration = http.getHeader(request.*, "hx-request") == null;

    var not_found = false;

    const parts = http.parseRequestParts(&request.*);

    if (self.map.get(parts.path)) |func| {
        try func.call(request.*, &writer);
    } else {
        not_found = true;
        try self.notFound.call(request.*, &writer);
    }

    if (needs_hydration) {
        var component_buffer = try std.ArrayList(u8).initCapacity(a, 1024);
        try ComponentsDirectory.tryUpdate(a);
        const arr = ComponentsDirectory.get().array;
        for (0..arr.len) |i| {
            try component_buffer.appendSlice(a, arr[i].content);
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
