const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
const zdotenv = @import("zdotenv");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const warn = std.log.warn;

pub const Home = struct {};
pub const HomeTemplate = zemplate.template.Template(Home, @embedFile("pages/home.html"));
pub fn home_handler(ctx: *HomeTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

pub const About = struct {};
pub const AboutTemplate = zemplate.template.Template(About, @embedFile("pages/about.html"));
pub fn about_handler(ctx: *AboutTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

pub const Info = struct {};
pub const InfoTemplate = zemplate.template.Template(Info, @embedFile("pages/info.html"));
pub fn info_handler(ctx: *InfoTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}
