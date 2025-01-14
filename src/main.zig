const std = @import("std");
const zap = @import("zap");
const routes = @import("routes");
const ArrayList = std.ArrayList;
const print = std.debug.print;

/// To be used for on_request and any other handler function
const HANDLER_ALLOCATOR_BUFFER_SIZE = 1024;
fn on_request(r: zap.Request) void {
    var buffer: [HANDLER_ALLOCATOR_BUFFER_SIZE]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var segments = routes.parse_path(r.path orelse routes.Route.Home.to_string(), allocator) catch |err| {
        std.debug.panic("failed to parse segments: {}", .{err});
    };

    const handler_fn = routes.Route.handler(&segments);

    handler_fn(&segments, r);
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = on_request,
        .public_folder = "serve",
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
