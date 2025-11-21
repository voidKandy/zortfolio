const std = @import("std");
const zemplate = @import("zemplate");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const log = std.log.scoped(.routes);
const Request = std.http.Server.Request;

pub const Home = struct { about: []u8 = undefined };
pub const HomeTemplate = zemplate.Template(Home, @embedFile("home.html"));
pub fn homeHandler(ctx: *HomeTemplate, r: Request, w: *std.Io.Writer) anyerror!void {
    _ = r;
    const file = try std.fs.cwd().openFile("./about.md", .{});
    const buffer = try ctx.allocator.alloc(u8, 1024 * 256);
    var reader = file.reader(&.{});
    const n = try reader.interface.readSliceShort(buffer);
    ctx.context.about = buffer[0..n];

    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit(ctx.allocator);
    // r.sendBody(body.items) catch return;
    try w.writeAll(body.items);
}

pub const Info = struct {};
pub const InfoTemplate = zemplate.Template(Info, @embedFile("info.html"));
pub fn infoHandler(ctx: *InfoTemplate, r: Request, w: *std.Io.Writer) anyerror!void {
    _ = r;
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit(ctx.allocator);

    try w.writeAll(body.items);
    // r.sendBody(body.items) catch return;
}
