const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
pub const routes = @import("routes.zig");
const music = @import("music.zig");
const blog = @import("blog.zig");
const middleware = @import("middleware.zig");

pub const std_options = std.Options{
    .log_level = .info,
    // .log_level = .warn,
};

// just a way to share our allocator via callback
pub const SharedAllocator = struct {
    // static
    var allocator: std.mem.Allocator = undefined;

    const Self = @This();

    // just a convenience function
    pub fn init(a: std.mem.Allocator) void {
        allocator = a;
    }

    // static function we can pass to the listener later
    pub fn getAllocator() std.mem.Allocator {
        return allocator;
    }
};

fn notFoundHandler(r: zap.Request) anyerror!void {
    r.setStatus(zap.http.StatusCode.not_found);

    const body = "<html><body><h1>404 NOT FOUND</h1></body></html>";
    _ = r.sendBody(body) catch |err| {
        std.debug.print("Error sending response: {any}\n", .{err});
    };
}

pub fn oldMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();
    SharedAllocator.init(allocator);

    const env_map = try std.process.getEnvMap(allocator);

    const port_str = env_map.get("PORT") orelse "3000";
    const port = try std.fmt.parseInt(usize, port_str, 10);

    var router = zap.Router.init(allocator, .{ .not_found = notFoundHandler });
    defer router.deinit();

    var music_info = try music.MusicInfo.build(allocator);
    defer music_info.deinit(allocator);
    var mtmp = music.MusicTemplate.init(music_info, allocator);
    var home = routes.HomeTemplate.init(routes.Home{}, allocator);
    var info = routes.InfoTemplate.init(routes.Info{}, allocator);

    try router.handle_func("/Home", &home, &routes.homeHandler);
    try router.handle_func_unbound("/Blog", &blog.blogHandler);
    try router.handle_func("/Music", &mtmp, &music.musicHandler);
    try router.handle_func("/Info", &info, &routes.infoHandler);

    var htmlHandler = try middleware.HtmlEndpoint.init(allocator, &router, null);
    defer htmlHandler.deinit(allocator);

    var hydrationHandler = middleware.HydrationMiddleware.init(htmlHandler.getHandler());

    var listener = try zap.Middleware.Listener(middleware.HydrationContext).init(
        .{
            .on_request = null, // must be null for middleware
            .public_folder = "serve",
            .port = port,
            .log = true,
            .max_clients = 100000,
        },
        hydrationHandler.getHandler(),
        SharedAllocator.getAllocator,
    );
    listener.listen() catch |err| {
        std.debug.print("\nLISTEN ERROR: {any}\n", .{err});
        return;
    };

    std.debug.print("TCP Listener is running\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}

test {
    std.testing.refAllDecls(@This());
}

pub fn main() !void {
    try @import("http.zig").main();
}
