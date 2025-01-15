const std = @import("std");
const zap = @import("zap");
const routes = @import("routes");
const ArrayList = std.ArrayList;
const print = std.debug.print;

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = routes.handle_request,
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
