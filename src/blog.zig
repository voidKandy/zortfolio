const std = @import("std");
const zemplate = @import("zemplate");
const http = @import("http.zig");
const ArrayList = std.ArrayList;
const Request = std.http.Server.Request;
const cache = @import("cache.zig");
const BlogDirectory = cache.CachedDirectory(BlogPostInfo, "blog");
const log = std.log.scoped(.blog);

const BlogMetadata = struct {
    path: []const u8,
    last_modified: i64,

    var map: std.StringHashMap(i64) = undefined;

    fn loadMap(a: std.mem.Allocator) !void {
        const json_bytes = @embedFile("blogsMetadata.json");
        const parsed = try std.json.parseFromSlice([]BlogMetadata, a, json_bytes, .{});
        const blogs = parsed.value;

        map = std.StringHashMap(i64).init(a);

        for (blogs) |item| {
            try map.put(item.path, item.last_modified);
        }

        return;
    }
};

pub const Blog = struct {
    allocator: std.mem.Allocator,
    pub fn init(a: std.mem.Allocator) !@This() {
        try BlogMetadata.loadMap(a);
        BlogDirectory.init(a);
        return .{
            .allocator = a,
        };
    }
    pub fn deinit(self: @This()) void {
        BlogMetadata.map.deinit();
        BlogDirectory.deinit(self.allocator);
    }
};

pub const CurrentBlogPage = struct {
    path: []const u8,
    name: []const u8,
    filename: []const u8,
    last_modified: []u8,
    content: []u8,
    /// Serialized []BlogPostInfo
    all_blogs_json: []u8,
};

const BlogPostInfo = struct {
    last_modified: i64,
    name: []u8,
    uri_path: []u8,
    file_name: []u8,
    content: []u8,

    fn getUriPath(name: []u8, allocator: std.mem.Allocator) ![]u8 {
        const name_cpy = try allocator.dupe(u8, name);
        std.mem.replaceScalar(u8, name_cpy, ' ', '-');
        return std.ascii.allocLowerString(allocator, name_cpy);
    }

    pub fn fromFile(dir: std.fs.Dir, path: []const u8, a: std.mem.Allocator) anyerror!@This() {
        const true_last_mod = BlogMetadata.map.get(path) orelse return error.NoMetadata;
        const file = try dir.openFile(path, .{});
        defer file.close();

        var split =
            std.mem.splitBackwardsScalar(u8, path, '.');
        const ext = split.first();

        if (!std.mem.eql(u8, ext, "md")) {
            return error.NotMarkdown;
        }

        const content = try file.readToEndAlloc(a, 8092);
        const post_name: []u8 = blk: {
            var spl = std.mem.splitScalar(u8, content, '\n');
            const firstline =
                spl.first();
            if (!std.mem.containsAtLeast(u8, firstline, 1, "#")) {
                const name = try a.alloc(u8, "Untitled".len);
                @memcpy(name, "Untitled");
                break :blk name;
            }

            const trimmed_header = std.mem.trim(u8, std.mem.trimLeft(u8, firstline, "#"), " \n");
            const name = try a.alloc(u8, trimmed_header.len);
            @memcpy(name, trimmed_header);
            break :blk name;
        };

        const file_name = try a.alloc(u8, path.len);
        @memcpy(file_name, path);
        const uri_path = try BlogPostInfo.getUriPath(post_name, a);

        return @This(){
            .last_modified = true_last_mod,
            .uri_path = uri_path,
            .file_name = file_name,
            .name = post_name,
            .content = content,
        };
    }
};

// pub fn getAllPosts(allocator: std.mem.Allocator) ![]BlogPostInfo {
//     var blog_dir = std.fs.cwd().openDir("blog", .{ .iterate = true }) catch |e| {
//         log.err("failed to open blog dir: {}\n", .{e});
//         return error.NoBlogDirectory;
//     };
//     var iter = blog_dir.iterate();
//     var postlist = try std.ArrayList(BlogPostInfo).initCapacity(allocator, iter.buf.len);
//     while (try iter.next()) |f| {
//         if (f.kind != .file) {
//             continue;
//         }
//         var split =
//             std.mem.splitBackwardsScalar(u8, f.name, '.');
//         const ext = split.first();
//         if (!std.mem.eql(u8, ext, "md")) {
//             continue;
//         }

//         const fullpath = try std.fmt.allocPrint(allocator, "blog/{s}", .{f.name});
//         const file = try std.fs.cwd().openFile(fullpath, .{});
//         defer file.close();
//         const last_modified = (try file.stat()).mtime;
//         const content = try file.readToEndAlloc(allocator, 8092);
//         const post_name: []u8 = blk: {
//             var spl = std.mem.splitScalar(u8, content, '\n');
//             const firstline =
//                 spl.first();
//             if (!std.mem.containsAtLeast(u8, firstline, 1, "#")) {
//                 const name = try allocator.alloc(u8, "Untitled".len);
//                 @memcpy(name, "Untitled");
//                 break :blk name;
//             }

//             const trimmed_header = std.mem.trim(u8, std.mem.trimLeft(u8, firstline, "#"), " \n");
//             const name = try allocator.alloc(u8, trimmed_header.len);
//             @memcpy(name, trimmed_header);
//             break :blk name;
//         };

//         const file_name = try allocator.alloc(u8, f.name.len);
//         @memcpy(file_name, f.name);
//         const path = try BlogPostInfo.getUriPath(post_name, allocator);

//         log.debug(
//             \\Appending Post:
//             \\ FileName: {s}
//             \\ PATH: {s}
//             \\ PostName: {s}
//             \\ Content:
//             \\ {s}
//         , .{ f.name, path, post_name, content });

//         const post = BlogPostInfo{
//             .last_modified = last_modified,
//             .uri_path = path,
//             .file_name = file_name,
//             .name = post_name,
//             .content = content,
//         };
//         try postlist.append(allocator, post);
//     }

//     return try postlist.toOwnedSlice(allocator);
// }

pub const BlogTemplate = zemplate.Template(CurrentBlogPage, @embedFile("pages/blog.html"));
fn getBlogPage(allocator: std.mem.Allocator, query_opt: ?[]const u8) !CurrentBlogPage {
    try BlogDirectory.tryUpdate(allocator);
    const all_posts = BlogDirectory.get().array;

    const postpath: []const u8 = blk: {
        if (query_opt) |query| {
            log.debug("QUERY: {s}", .{query});
            var split =
                std.mem.splitBackwardsSequence(u8, query, "post=");
            const first = split.first();
            if (std.mem.containsAtLeast(u8, first, 1, "&")) {
                var s = std.mem.splitScalar(u8, first, '&');
                break :blk s.first();
            }
            break :blk first;
        } else {
            break :blk all_posts[0].uri_path;
        }
    };

    log.debug("GOT POSTNAME: {s}\n", .{postpath});
    var post: ?BlogPostInfo = null;

    for (all_posts) |p| {
        if (std.mem.eql(u8, p.uri_path, postpath)) {
            post = p;
        }
    }
    var out: std.io.Writer.Allocating = .init(allocator);
    try std.json.Stringify.value(all_posts, .{ .whitespace = .indent_2 }, &out.writer);
    var arr = out.toArrayList();

    if (post == null) {
        log.err("the name {s} does not have an associated post\n", .{postpath});
        return error.NoMatchingPostname;
    }

    log.debug(
        \\POST:
        \\  NAME: {s}
        \\  FileName: {s}
        \\  CONTENT LEN: {d}
    , .{ post.?.name, post.?.file_name, post.?.content.len });
    const last_modified_string = try std.fmt.allocPrint(allocator, "{d}", .{post.?.last_modified});

    return CurrentBlogPage{
        .path = post.?.uri_path,
        .name = post.?.name,
        .filename = post.?.file_name,
        .last_modified = last_modified_string,
        .content = post.?.content,
        .all_blogs_json = try arr.toOwnedSlice(allocator),
    };
}

pub fn blogHandler(ctx: *Blog, r: Request, w: *std.Io.Writer) anyerror!void {
    // const dir = BlogDirectory.get();

    // for (0..dir.array.len) |i| {
    //     log.warn(
    //         \\ {s} : {s}
    //     , .{
    //         dir.array[i].name,
    //         dir.array[i].path,
    //     });
    // }
    const parts = http.parse(&r);
    const blog = getBlogPage(ctx.allocator, parts.query) catch |e| {
        log.err("failed to get blog post: {any}\n", .{e});
        return;
    };
    if (parts.query == null) {
        const redirect = try std.fmt.allocPrint(ctx.allocator, "/Blog?post={s}", .{blog.path});
        defer ctx.allocator.free(redirect);
        try @constCast(&r).respond("", .{ .status = .found, .extra_headers = &.{.{ .name = "Location", .value = redirect }} });
        return;
    }
    var template = BlogTemplate.init(blog, ctx.allocator);
    var body = template.render() catch |err| {
        std.debug.panic("Failed to render template: {}", .{err});
    };
    defer body.deinit(ctx.allocator);
    try w.writeAll(body.items);
    // try r.sendBody(body.items);
}
