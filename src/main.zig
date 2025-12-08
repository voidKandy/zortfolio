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
    var server = zyph.Server.init(allocator, try cwd.openFile("pages/index.html", .{}), try cwd.openDir("serve", .{ .iterate = true }));
    defer server.deinit();

    var music_info = try music.MusicInfo.build(allocator);
    defer music_info.deinit(allocator);
    var blg_dat = try blog.StaticBlogData.init(allocator);
    defer blg_dat.deinit();

    try server.routes.registerHypermediaEndpoint("/", &.{}, &struct {
        fn handler(obj: *@TypeOf(.{}), a: std.mem.Allocator, _: Request, w: *std.Io.Writer) anyerror!void {
            var t = EmptyTemplate.init(obj.*);
            const render = try t.render(a, @embedFile("home.html"), .{});
            try w.writeAll(render);
        }
    }.handler);

    try server.routes.registerHypermediaEndpoint("/Info", &.{}, &struct {
        fn handler(obj: *@TypeOf(.{}), a: std.mem.Allocator, _: Request, w: *std.Io.Writer) anyerror!void {
            var t = EmptyTemplate.init(obj.*);
            const render = try t.render(a, @embedFile("info.html"), .{});
            try w.writeAll(render);
        }
    }.handler);

    try server.routes.registerHypermediaEndpoint("/Music", &music_info, &music.musicHandler);
    try server.routes.registerHypermediaEndpoint("/Blog", &blg_dat, &blog.blogHandler);

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
