const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
const zdotenv = @import("zdotenv");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const warn = std.log.warn;

pub const ComponentCache = std.StringHashMap(ComponentInfo);
pub fn init_component_cache(a: std.mem.Allocator, parent_path: []const u8) !ComponentCache {
    var map = ComponentCache.init(a);
    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(parent_path, .{ .iterate = true });
    var iter = dir.iterate();

    while (try iter.next()) |f| {
        if (f.kind != .file) {
            continue;
        }

        const info = try ComponentInfo.new(f.name, a);
        try map.put(info.name, info);
    }

    return map;
}

pub const ComponentInfo = struct {
    path: []u8,
    content: []u8,
    name: []u8,

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.content);
        allocator.free(self.path);
    }

    fn new(path: []const u8, allocator: std.mem.Allocator) !@This() {
        var split = std.mem.splitBackwards(u8, path, ".");

        if (!std.mem.eql(u8, split.first(), "html")) {
            return error.NotHTML;
        }
        const filename = split.next() orelse return error.InvalidFilename;

        var uppercase_idcs: []usize = try allocator.alloc(usize, filename.len);
        var len: usize = 0;
        for (filename, 0..) |ch, i| {
            if (std.ascii.isUpper(ch)) {
                uppercase_idcs[len] = i;
                len += 1;
            }
        }
        const component_name: []u8 = try allocator.alloc(u8, filename.len + len);

        var i: usize = 0;
        for (filename) |ch| {
            if (std.ascii.isUpper(ch)) {
                component_name[i] = '-';
                i += 1;
                component_name[i] = std.ascii.toLower(ch);
            } else {
                component_name[i] = ch;
            }
            i += 1;
        }

        const fullpath = try std.fmt.allocPrint(allocator, "components/{s}", .{path});
        const file = try std.fs.cwd().openFile(fullpath, .{});
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 8092);

        return @This(){ .path = fullpath, .name = component_name, .content = content };
    }
};

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
