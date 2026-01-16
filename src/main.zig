const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
const music = @import("music.zig");
const blog = @import("blog.zig");
const zyph = @import("zyph");
const Request = std.http.Server.Request;

pub const std_options = std.Options{
    // .log_level = .debug,
    .log_level = .warn,
};

const EmptyTemplate = zemplate.Template(@TypeOf(.{}));

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    defer if (gpa.detectLeaks()) std.log.err("LEAKS DETECTED IN MAIN ALLOCATOR\n", .{});

    const allocator = gpa.allocator();
    const cwd = std.fs.cwd();
    var server = zyph.Server.init(allocator, try cwd.openDir("serve", .{ .iterate = true }));
    defer server.deinit();

    var hydration_context = try zyph.hydration_middleware.Context.init(allocator, try std.fs.cwd().openFile("pages/index.html", .{}));
    defer hydration_context.deinit(allocator);
    try server.middlewares.put(
        zyph.hydration_middleware.NAME,
        zyph.Middleware.init(.post, &hydration_context, &zyph.hydration_middleware.handler),
    );

    var music_info = try music.MusicInfo.build(allocator);
    defer music_info.deinit(allocator);
    var blg_dat = try blog.StaticBlogDataHandle.init(allocator);
    defer blg_dat.deinit();

    for (&[_]zyph.Server.RouteHandler{
        try server.registerHypermediaEndpoint("/", &.{}, &struct {
            fn handler(obj: *@TypeOf(.{}), a: std.mem.Allocator, _: Request, w: *std.Io.Writer) anyerror!void {
                var t = try EmptyTemplate.init(a, obj.*);
                defer t.deinit();
                const render = try t.render(@embedFile("home.html"), .{});
                try w.writeAll(render);
            }
        }.handler),

        try server.registerHypermediaEndpoint("/Info", &.{}, &struct {
            fn handler(obj: *@TypeOf(.{}), a: std.mem.Allocator, _: Request, w: *std.Io.Writer) anyerror!void {
                var t = try EmptyTemplate.init(a, obj.*);
                defer t.deinit();
                const render = try t.render(@embedFile("info.html"), .{});
                try w.writeAll(render);
            }
        }.handler),

        try server.registerHypermediaEndpoint("/Music", &music_info, &music.musicHandler),
        try server.registerHypermediaEndpoint("/Blog", &blg_dat, &blog.blogHandler),
    }) |route_handler| {
        try route_handler.addMiddlewares(.post, &.{zyph.hydration_middleware.NAME});
    }

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const port_str = env_map.get("PORT") orelse "3000";
    const port = try std.fmt.parseInt(u16, port_str, 10);
    const addr = try std.net.Address.parseIp("0.0.0.0", port);
    try server.startServer(addr, .{ .reuse_address = true });

    try server.listen();
}

test {
    std.testing.refAllDecls(@This());
}
