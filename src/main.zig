const std = @import("std");
const zap = @import("zap");
const routes = @import("routes");
const ArrayList = std.ArrayList;
const print = std.debug.print;

fn not_found_handler(r: zap.Request) void {
    r.setStatus(zap.StatusCode.not_found);

    const body = "<html><body><h1>404 NOT FOUND</h1></body></html>";
    _ = r.sendBody(body) catch |err| {
        std.debug.print("Error sending response: {any}\n", .{err});
    };
}

fn on_request_verbose(r: zap.Request) void {
    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }
    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();

    var router = zap.Router.init(allocator, .{ .not_found = not_found_handler });
    defer router.deinit();

    var home = try routes.HomeTemplate.init(routes.Home{ .field = "value" }, allocator);
    var about = try routes.AboutTemplate.init(routes.About{}, allocator);

    try router.handle_func_unbound("/", on_request_verbose);

    try router.handle_func("/home", &home, &routes.home_handler);
    try router.handle_func("/about", &about, &routes.about_handler);

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = router.on_request_handler(),
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
