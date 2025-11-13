const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
pub const routes = @import("routes.zig");
const music = @import("music.zig");
const blog = @import("blog.zig");

const Dispatcher = @import("http.zig").Dispatcher;

pub const std_options = std.Options{
    // .log_level = .info,
    .log_level = .warn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    defer if (gpa.detectLeaks()) std.log.err("LEAKS DETECTED IN MAIN ALLOCATOR\n", .{});
    var allocator = gpa.allocator();
    var dispatcher = Dispatcher.init(allocator, try std.fs.cwd().openDir("serve", .{ .iterate = true }));

    var music_info = try music.MusicInfo.build(allocator);
    defer music_info.deinit(allocator);
    var mtmp = music.MusicTemplate.init(music_info, allocator);
    var home = routes.HomeTemplate.init(routes.Home{}, allocator);
    var info = routes.InfoTemplate.init(routes.Info{}, allocator);

    try dispatcher.router.registerStatefulHandler("/Home", &home, &routes.homeHandler);
    try dispatcher.router.registerStatefulHandler("/Blog", &allocator, &blog.blogHandler);
    try dispatcher.router.registerStatefulHandler("/Music", &mtmp, &music.musicHandler);
    try dispatcher.router.registerStatefulHandler("/Info", &info, &routes.infoHandler);

    // try router.withTls(std.fs.cwd(), "local_ssl/localhost.crt", "local_ssl/localhost.key");
    const addr = try std.net.Address.parseIp("0.0.0.0", 3000);
    try dispatcher.startServer(addr, .{ .reuse_address = true });
    defer dispatcher.deinit();

    try dispatcher.listen();
}

test {
    std.testing.refAllDecls(@This());
}
