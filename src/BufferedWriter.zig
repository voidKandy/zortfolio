const std = @import("std");
const log = std.log.scoped(.BufferedWriter);

allocator: std.mem.Allocator,
buffer: std.ArrayList(u8),
interface: std.Io.Writer,

const Self = @This();

const vtable = std.Io.Writer.VTable{
    .drain = Self.drain,
};

pub fn init(allocator: std.mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .buffer = try std.ArrayList(u8).initCapacity(allocator, 2048),
        .interface = undefined,
    };

    self.interface = .{
        .buffer = &[_]u8{},
        .vtable = &vtable,
    };

    return self;
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) error{WriteFailed}!usize {
    _ = splat;
    const self: *@This() = @fieldParentPtr("interface", io_w);
    self.buffer.appendSlice(self.allocator, data[0]) catch |e| {
        log.err(
            \\ Drain error: {any}
        , .{e});
        return error.WriteFailed;
    };
    return data[0].len;
}

pub fn bytes(self: *Self) []const u8 {
    return self.buffer.items;
}
