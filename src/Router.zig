const std = @import("std");
const log = std.log.scoped(.Routere);

const Request = std.http.Server.Request;
const BufferedWriter = @import("BufferedWriter.zig");

pub const RouteFuncReturn = enum {
    /// The route returned a response and consumed the BufferedWriter
    Terminate,
    /// The route wrote to the BufferedWriter but didn't actually respond
    Continue,
};

pub const StatelessFunc =
    *const fn (r: *Request, writer: *BufferedWriter) anyerror!RouteFuncReturn;

pub const StatefullFunc = *fn (*const anyopaque, *Request, *BufferedWriter) anyerror!RouteFuncReturn;

const RouteFunc = union(enum) {
    stateless: StatelessFunc,
    statefull: struct {
        state_ptr: usize,
        func_ptr: usize,
    },
};

const RoutesMap = std.StringHashMap(RouteFunc);
const Self = @This();

map: RoutesMap,

pub fn init(a: std.mem.Allocator) Self {
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
    if (self.map.get(request.head.target)) |func| {
        log.info(
            \\ GOT FUNC: {any}
        , .{func});
        var writer = try BufferedWriter.init(a);
        defer writer.deinit(a);
        const ret = switch (func) {
            .statefull => |b| try @call(.auto, @as(StatefullFunc, @ptrFromInt(b.func_ptr)), .{ @as(*anyopaque, @ptrFromInt(b.state_ptr)), request, &writer }),
            .stateless => |f| try f(request, &writer),
        };

        switch (ret) {
            .Terminate => {
                log.info(
                    \\ Writer buffer: {s}
                , .{writer.buffer.items});
                try request.respond(writer.buffer.items, .{});
            },
            .Continue => {
                log.info(
                    \\ Writer buffer: {s}
                , .{writer.buffer.items});
                try request.respond(writer.buffer.items, .{});
            },
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
pub fn registerStatefullHandler(self: *Self, path: []const u8, instance: *anyopaque, func: anytype) !void {
    // Introspection checks on handler type
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
        if (arg_2_type != *Request) {
            @compileError("Expected func's second argument to be of type *Request. Found " ++
                @typeName(arg_2_type));
        }

        const arg_3_type = f.params[2].type.?;
        if (arg_3_type != *BufferedWriter) {
            @compileError("Expected func's second argument to be of type *BufferedWriter. Found " ++
                @typeName(arg_3_type));
        }

        if (!ret: {
            const ret_info = @typeInfo(f.return_type orelse break :ret false);
            const set = ret_info.error_union.error_set;
            const payload = ret_info.error_union.payload;

            break :ret (payload == RouteFuncReturn and set == anyerror);
        }) {
            @compileError("Expected func's return type to be anyerror!RouteFuncReturn. Found " ++
                @typeName(f.return_type.?));
        }
    }

    if (path.len == 0) {
        return error.EmptyPath;
    }

    if (self.map.contains(path)) {
        return error.AlreadyExists;
    }

    try self.map.put(path, RouteFunc{ .statefull = .{
        .state_ptr = @intFromPtr(instance),
        .func_ptr = @intFromPtr(func),
    } });
}
