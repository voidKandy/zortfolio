const std = @import("std");
const zap = @import("zap");
const template = @import("template");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const warn = std.log.warn;

pub const Home = struct { field: []const u8 };
pub const HomeTemplate = template.Template(Home, "pages/home.html");
pub fn home_handler(ctx: *HomeTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

pub const About = struct {};
pub const AboutTemplate = template.Template(About, "pages/about.html");
pub fn about_handler(ctx: *AboutTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}
