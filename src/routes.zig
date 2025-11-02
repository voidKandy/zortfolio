const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
const zdotenv = @import("zdotenv");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const warn = std.log.warn;

pub const Home = struct { about: []u8 = undefined };
pub const HomeTemplate = zemplate.template.Template(Home, @embedFile("pages/home.html"));
pub fn home_handler(ctx: *HomeTemplate, r: zap.Request) anyerror!void {
    const file = try std.fs.cwd().openFile("./about.md", .{});
    const buffer = try ctx.allocator.alloc(u8, 1024 * 256);
    var reader = file.reader(&.{});
    const n = try reader.interface.readSliceShort(buffer);
    ctx.context.about = buffer[0..n];

    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit(ctx.allocator);
    r.sendBody(body.items) catch return;
}

pub const Info = struct {};
pub const InfoTemplate = zemplate.template.Template(Info, @embedFile("pages/info.html"));
pub fn info_handler(ctx: *InfoTemplate, r: zap.Request) anyerror!void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit(ctx.allocator);

    r.sendBody(body.items) catch return;
}
