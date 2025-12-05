const std = @import("std");
const zemplate = @import("zemplate");
const zyph = @import("zyph");
const ArrayList = std.ArrayList;
const Request = std.http.Server.Request;
const BlogDirectory = zyph.cache.CachedDirectory(BlogPostInfo, "serve/blog");
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

pub const StaticBlogData = struct {
    pub fn init(a: std.mem.Allocator) !@This() {
        try BlogMetadata.loadMap(a);
        BlogDirectory.init(a);
        return .{};
    }
    pub fn deinit(self: @This()) void {
        _ = self;
        BlogMetadata.map.deinit();
        BlogDirectory.deinit();
    }
};

pub const CurrentBlogPage = struct {
    path: []const u8,
    name: []const u8,
    filename: []const u8,
    last_modified: []u8,
    all_blogs: []ClientsideBlogData,

    fn deinit(self: @This(), a: std.mem.Allocator) void {
        a.free(self.last_modified);
        a.free(self.all_blogs);
    }
};

const ClientsideBlogData =
    struct {
        last_modified: i64,
        name: []u8,
        uri_path: []u8,
    };

const BlogPostInfo = struct {
    last_modified: i64,
    name: []u8,
    uri_path: []u8,
    file_name: []u8,

    /// Currently not actually used at all, could likely be removed
    content: []u8,

    fn getUriPath(name: []u8, allocator: std.mem.Allocator) ![]u8 {
        const name_cpy = try allocator.dupe(u8, name);
        std.mem.replaceScalar(u8, name_cpy, ' ', '-');
        return std.ascii.allocLowerString(allocator, name_cpy);
    }

    pub fn preImage(self: @This()) []const u8 {
        return self.uri_path;
    }

    pub fn fromFile(dir: std.fs.Dir, path: []const u8, a: std.mem.Allocator) anyerror!@This() {
        const map = BlogMetadata.map;
        const true_last_mod = map.get(path) orelse return error.NoMetadata;
        const file = try dir.openFile(path, .{});
        defer file.close();

        var split =
            std.mem.splitBackwardsScalar(u8, path, '.');
        const ext = split.first();

        if (!std.mem.eql(u8, ext, "md")) {
            return error.NotMarkdown;
        }

        const content = try file.readToEndAlloc(a, 1024 * 16);
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

/// Just some optimization BS
var default_blog_path: ?[]const u8 = null;
inline fn getDefaultBlogPath() ![]const u8 {
    if (default_blog_path) |p| return p;
    try BlogDirectory.tryUpdate();
    const all_posts = BlogDirectory.get().map;
    var iter = all_posts.valueIterator();
    var oldest_blog_post: ?*BlogPostInfo = null;
    while (iter.next()) |n| {
        if (oldest_blog_post) |p| {
            if (n.last_modified < p.*.last_modified) oldest_blog_post = n;
        } else oldest_blog_post = n;
    }

    default_blog_path = oldest_blog_post.?.uri_path;
    return default_blog_path.?;
}

/// returned blog page needs to be freed
fn getBlogPage(allocator: std.mem.Allocator, postpath: []const u8) !?CurrentBlogPage {
    try BlogDirectory.tryUpdate();
    const all_posts = BlogDirectory.get().map;

    const post = all_posts.get(std.hash_map.hashString(postpath));

    // This is a workaround for the fact that zemplate doesnt have control flow
    // we serialize the data and just pass it to the client as json
    var iter = all_posts.valueIterator();
    const blogs_data = try allocator.alloc(ClientsideBlogData, all_posts.count());
    // defer allocator.free(blogs_data);
    var i: usize = 0;
    while (iter.next()) |p| : (i += 1) {
        blogs_data[i] = .{
            .last_modified = p.last_modified,
            .name = p.name,
            .uri_path = p.uri_path,
        };
    }

    if (post == null) {
        log.err("the name {s} does not have an associated post\n", .{postpath});
        return error.NotFound;
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
        .all_blogs = blogs_data,
    };
}

const Template = zemplate.Template(CurrentBlogPage);

pub fn blogHandler(_: *StaticBlogData, a: std.mem.Allocator, r: Request, w: *std.Io.Writer) anyerror!void {
    const parts = zyph.parseRequestParts(&r);

    const postpath: []const u8 = blk: {
        if (parts.query) |query| {
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
            break :blk try getDefaultBlogPath();
        }
    };

    const blog = getBlogPage(a, postpath) catch |e| {
        if (e == error.NotFound) return e;

        log.err("failed to get blog post: {any}\n", .{e});
        return;
    } orelse return error.NotFound;
    defer blog.deinit(a);
    if (parts.query == null) {
        const redirect = try std.fmt.allocPrint(a, "/Blog?post={s}", .{blog.path});
        log.warn(
            \\ Redirecting to {s}
        , .{redirect});

        const extra_headers: []const std.http.Header =
            if (zyph.getHeader(r, "x-hydrated")) |v|
                &.{ .{ .name = "Location", .value = redirect }, .{ .name = "x-hydrated", .value = v } }
            else
                &.{
                    .{ .name = "Location", .value = redirect },
                };

        defer a.free(redirect);
        try @constCast(&r).respond("", .{
            .status = .found,
            .extra_headers = extra_headers,
        });
        return;
    }
    var t = Template.init(blog);
    const body = t.render(a, @embedFile("blog.html"), .{}) catch |err| {
        std.debug.panic("Failed to render template: {}", .{err});
    };
    try w.writeAll(body);
}
