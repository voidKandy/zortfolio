const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
pub const routes = @import("routes.zig");
const music = @import("music.zig");
const blog = @import("blog.zig");

const Dispatcher = @import("http.zig").Dispatcher;

pub const std_options = std.Options{
    // .log_level = .debug,
    .log_level = .warn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    defer if (gpa.detectLeaks()) std.log.err("LEAKS DETECTED IN MAIN ALLOCATOR\n", .{});
    const allocator = gpa.allocator();
    var dispatcher = Dispatcher.init(allocator, try std.fs.cwd().openDir("serve", .{ .iterate = true }));
    defer dispatcher.deinit();

    var music_info = try music.MusicInfo.build(allocator);
    defer music_info.deinit(allocator);
    var mtmp = music.MusicTemplate.init(music_info);
    var home = routes.HomeTemplate.init(routes.Home{});
    var info = routes.InfoTemplate.init(routes.Info{});
    var blg_dat = try blog.StaticBlogData.init(allocator);
    defer blg_dat.deinit();

    try dispatcher.routes_map.registerStatefulHandler("/", &home, &routes.homeHandler);
    try dispatcher.routes_map.registerStatefulHandler("/Music", &mtmp, &music.musicHandler);
    try dispatcher.routes_map.registerStatefulHandler("/Info", &info, &routes.infoHandler);
    try dispatcher.routes_map.registerStatefulHandler("/Blog", &blg_dat, &blog.blogHandler);

    // try router.withTls(std.fs.cwd(), "local_ssl/localhost.crt", "local_ssl/localhost.key");
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const port_str = env_map.get("PORT") orelse "3000";
    const port = try std.fmt.parseInt(u16, port_str, 10);
    const addr = try std.net.Address.parseIp("0.0.0.0", port);
    try dispatcher.startServer(addr, .{ .reuse_address = true });

    try dispatcher.listen();
}

test {
    std.testing.refAllDecls(@This());
}
