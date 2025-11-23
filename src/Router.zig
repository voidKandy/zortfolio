const std = @import("std");
const log = std.log.scoped(.Router);
const http = @import("http.zig");
const ComponentsDirectory = @import("components.zig").ComponentsDirectory;

const Request = std.http.Server.Request;
const BufferedWriter = @import("BufferedWriter.zig");

const Self = @This();

map_ptr: *const @import("RouteMap.zig"),
delivered_components: std.AutoHashMap(u64, void),

pub fn init(a: std.mem.Allocator, map_ptr: *const @import("RouteMap.zig")) Self {
    return .{
        .map_ptr = map_ptr,
        .delivered_components = std.AutoHashMap(u64, void).init(a),
    };
}

pub fn deinit(
    self: *Self,
) void {
    self.delivered_components.deinit();
}
