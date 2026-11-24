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

const Environ = enum { dev, prod };

fn getCerts(map: *const std.process.Environ.Map) struct {
    cert: []const u8,
    key: []const u8,
} {
    const environ = map.get("ENVIRONMENT") orelse e: {
        std.log.warn("ENVIRONMENT variable not set, defaulting to dev environment", .{});
        break :e "0";
    };
    const dev_or_prod: Environ = @fromBackingInt(std.fmt.parseInt(@typeInfo(Environ).@"enum".tag_type, environ, 10) catch std.debug.panic(
        "ENVIRONMENT env variable is an invalid value: '{s}'",
        .{environ},
    ));

    return switch (dev_or_prod) {
        .dev => .{
            .cert = "local_ssl/localhost.crt",
            .key = "local_ssl/localhost.key",
        },
        .prod => .{
            .cert = "ssl-bundle/domain.cert.pem",
            .key = "ssl-bundle/private.key.pem",
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var it = init.environ_map.iterator();
    while (it.next()) |entry| std.debug.print("env key: '{s}'\n", .{entry.key_ptr.*});
    var server = zyph.Server.init(allocator, init.io, "serve");

    const certs = getCerts(init.environ_map);
    try server.withTls(init.io, certs.cert, certs.key);
    defer server.deinit();

    var hydration_context = try zyph.hydration_middleware.Context.init(
        allocator,
        init.io,
        "components",
        try std.Io.Dir.cwd().openFile(init.io, "pages/layout.html", .{}),
    );
    defer hydration_context.deinit(allocator);
    try server.middlewares.put(
        zyph.hydration_middleware.NAME,
        zyph.Middleware.init(.post, &hydration_context, &zyph.hydration_middleware.handler),
    );

    var music_info = try music.MusicInfo.build(allocator, init.io, init.environ_map);
    defer music_info.deinit(allocator);
    var blg_dat = try blog.StaticBlogDataHandle.init(allocator, init.io);
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

    const port_str = init.environ_map.get("PORT") orelse "3000";
    const port = try std.fmt.parseInt(u16, port_str, 10);
    const addr = try std.Io.net.IpAddress.parse("0.0.0.0", port);
    try server.startServer(&addr, .{ .reuse_address = true });

    try server.listen();
}

test {
    std.testing.refAllDecls(@This());
}
