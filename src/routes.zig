const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const log = std.log.scoped(.routes);
const Request = std.http.Server.Request;

pub const Home = struct { about: []const u8 = @embedFile("about.md") };
pub const HomeTemplate = zemplate.Template(Home, @embedFile("home.html"));
pub fn homeHandler(ctx: *HomeTemplate, a: std.mem.Allocator, r: Request, w: *std.Io.Writer) anyerror!void {
    _ = r;
    const body = ctx.render(a, .{}) catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer a.free(body);
    try w.writeAll(body);
}
pub const Info = struct {};
pub const InfoTemplate = zemplate.Template(Info, @embedFile("info.html"));
pub fn infoHandler(ctx: *InfoTemplate, a: std.mem.Allocator, r: Request, w: *std.Io.Writer) anyerror!void {
    _ = r;
    const body = ctx.render(a, .{}) catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };

    defer a.free(body);
    try w.writeAll(body);
}
