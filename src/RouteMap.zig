const std = @import("std");
const log = std.log.scoped(.RouterMap);
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

    pub fn call(self: @This(), request: Request, writer: *BufferedWriter) anyerror!void {
        switch (self) {
            .stateful => |b| try @call(.auto, @as(StatefulFunc, @ptrFromInt(b.func_ptr)), .{ @as(*anyopaque, @ptrFromInt(b.state_ptr)), request, &writer.interface }),
            .stateless => |f| try f(request, &writer.interface),
        }
    }
};

map: std.StringHashMap(RouteFunc),

notFound: RouteFunc = .{ .stateless = &struct {
    fn handle(r: Request, w: *std.Io.Writer) anyerror!void {
        _ = r;
        try w.writeAll(@embedFile("404.html"));
    }
}.handle },

const Self = @This();
pub fn init(a: std.mem.Allocator) Self {
    return .{
        .map = std.StringHashMap(RouteFunc).init(a),
    };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
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
