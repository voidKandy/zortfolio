const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
const zdotenv = @import("zdotenv");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const log = std.log.scoped(.blog);

pub const BlogPage = struct {
    current_path: []const u8,
    current_name: []const u8,
    current_filename: []const u8,
    current_last_modified: []u8,
    current_content: []u8,
    /// Serialized []BlogPostInfo
    all_blogs_json: []u8,
};

const BlogPostInfo = struct {
    last_modified: i128,
    name: []u8,
    path: []u8,
    file_name: []u8,
    content: []u8,

    fn get_path(name: []u8, allocator: std.mem.Allocator) ![]u8 {
        const name_cpy = try allocator.dupe(u8, name);
        std.mem.replaceScalar(u8, name_cpy, ' ', '-');
        return std.ascii.allocLowerString(allocator, name_cpy);
    }
};

pub fn getAllPosts(allocator: std.mem.Allocator) ![]BlogPostInfo {
    var blog_dir = std.fs.cwd().openDir("blog", .{ .iterate = true }) catch |e| {
        std.log.err("failed to open blog dir: {}\n", .{e});
        return error.NoBlogDirectory;
    };
    var iter = blog_dir.iterate();
    var postlist = try std.ArrayList(BlogPostInfo).initCapacity(allocator, iter.buf.len);
    while (try iter.next()) |f| {
        if (f.kind != .file) {
            continue;
        }
        var split =
            std.mem.splitBackwardsScalar(u8, f.name, '.');
        const ext = split.first();
        if (!std.mem.eql(u8, ext, "md")) {
            continue;
        }

        const fullpath = try std.fmt.allocPrint(allocator, "blog/{s}", .{f.name});
        const file = try std.fs.cwd().openFile(fullpath, .{});
        defer file.close();
        const last_modified = (try file.stat()).mtime;
        const content = try file.readToEndAlloc(allocator, 8092);
        const post_name: []u8 = blk: {
            var spl = std.mem.splitScalar(u8, content, '\n');
            const firstline =
                spl.first();
            if (!std.mem.containsAtLeast(u8, firstline, 1, "#")) {
                const name = try allocator.alloc(u8, "Untitled".len);
                @memcpy(name, "Untitled");
                break :blk name;
            }

            const trimmed_header = std.mem.trim(u8, std.mem.trimLeft(u8, firstline, "#"), " \n");
            const name = try allocator.alloc(u8, trimmed_header.len);
            @memcpy(name, trimmed_header);
            break :blk name;
        };

        const file_name = try allocator.alloc(u8, f.name.len);
        @memcpy(file_name, f.name);
        const path = try BlogPostInfo.get_path(post_name, allocator);

        log.debug(
            \\Appending Post:
            \\ FileName: {s}
            \\ PATH: {s}
            \\ PostName: {s}
            \\ Content:
            \\ {s}
        , .{ f.name, path, post_name, content });

        const post = BlogPostInfo{
            .last_modified = last_modified,
            .path = path,
            .file_name = file_name,
            .name = post_name,
            .content = content,
        };
        try postlist.append(allocator, post);
    }

    return try postlist.toOwnedSlice(allocator);
}

pub const BlogTemplate = zemplate.Template(BlogPage, @embedFile("pages/blog.html"));
fn getBlogPage(allocator: std.mem.Allocator, query_opt: ?[]const u8) !BlogPage {
    const all_posts = try getAllPosts(allocator);
    defer allocator.free(all_posts);

    const postpath: []const u8 = blk: {
        if (query_opt) |query| {
            std.log.warn("QUERY: {s}", .{query});
            var split =
                std.mem.splitBackwardsSequence(u8, query, "post=");
            const first = split.first();
            if (std.mem.containsAtLeast(u8, first, 1, "&")) {
                var s = std.mem.splitScalar(u8, first, '&');
                break :blk s.first();
            }
            break :blk first;
        } else {
            break :blk all_posts[0].path;
        }
    };

    std.log.warn("GOT POSTNAME: {s}\n", .{postpath});
    // var all_blog_json_str = ArrayList(u8).init(allocator);
    var post: ?BlogPostInfo = null;

    var out: std.io.Writer.Allocating = .init(allocator);
    try std.json.Stringify.value(all_posts, .{ .whitespace = .indent_2 }, &out.writer);
    var arr = out.toArrayList();

    // const json = try std.json.Stringify.valueAlloc(allocator, all_posts, .{});
    for (all_posts) |p| {
        //     try all_blog_json_str.appendSlice(json);
        if (std.mem.eql(u8, p.path, postpath)) {
            post = p;
        }
    }

    if (post == null) {
        std.log.err("the name {s} does not have an associated post\n", .{postpath});
        return error.NoMatchingPostname;
    }

    // const all_blog_paths =
    // std.mem.trimRight(u8, try all_blog_paths_str.toOwnedSlice(), ", ");

    std.log.warn(
        \\POST:
        \\  NAME: {s}
        \\  FileName: {s}
        \\  CONTENT: {s}
        \\  ALL: {s}
    , .{ post.?.name, post.?.file_name, post.?.content, arr.items });
    const last_modified_string = try std.fmt.allocPrint(allocator, "{d}", .{post.?.last_modified});

    return BlogPage{
        .current_path = post.?.path,
        .current_name = post.?.name,
        .current_filename = post.?.file_name,
        .current_last_modified = last_modified_string,
        .current_content = post.?.content,
        .all_blogs_json = try arr.toOwnedSlice(allocator),
    };
}

pub fn blog_handler(r: zap.Request) anyerror!void {
    std.log.warn("IN BLOG HANDLER", .{});
    const allocator = @import("root").SharedAllocator.getAllocator();

    const blog = getBlogPage(allocator, r.query) catch |e| {
        std.log.err("failed to get blog post: {}\n", .{e});
        return;
    };

    var template = BlogTemplate.init(blog, allocator);
    var body = template.render() catch |err| {
        std.debug.panic("Failed to render template: {}", .{err});
    };
    defer body.deinit(allocator);
    try r.sendBody(body.items);
}
