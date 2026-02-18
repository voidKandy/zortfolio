const std = @import("std");
const BlogMetadata = @import("blog_metadata").Metadata;
const ArrayList = std.ArrayList;
const Request = std.http.Server.Request;

const zemplate = @import("zemplate");
const zyph = @import("zyph");

const BlogDirectory = zyph.cache.CachedDirectory(BlogPostInfo, "serve/blog");
const log = std.log.scoped(.blog);

pub const StaticBlogDataHandle = struct {
    /// Same as in tools/read_blog_post_metadata.zig
    var INFO_MAP: std.StringHashMap(struct {
        last_modified: i64,
        created: i64,
    }) = undefined;

    fn loadMap(a: std.mem.Allocator) !void {
        const json_bytes = @embedFile("blogsMetadata.json");

        const parsed = try std.json.parseFromSlice([]BlogMetadata, a, json_bytes, .{});

        const blogs = parsed.value;

        INFO_MAP = .init(a);

        for (blogs) |item| {
            try INFO_MAP.put(item.path, .{
                .last_modified = item.last_modified,
                .created = item.created,
            });
        }

        return;
    }

    pub fn init(a: std.mem.Allocator) !@This() {
        try loadMap(a);
        BlogDirectory.init(a);
        return .{};
    }

    pub fn deinit(_: @This()) void {
        INFO_MAP.deinit();
        BlogDirectory.deinit();
    }
};

pub const CurrentBlogPage = struct {
    path: []const u8,
    name: []const u8,
    filename: []const u8,
    last_modified: i64,
    created: i64,
    all_blogs: []ClientsideBlogData,
};

const ClientsideBlogData = struct {
    last_modified: i64,
    created: i64,
    name: []u8,
    uri_path: []u8,
};

const BlogPostInfo = struct {
    last_modified: i64,
    created: i64,
    name: []u8,
    uri_path: []u8,
    file_name: []u8,

    fn getUriPath(name: []u8, allocator: std.mem.Allocator) ![]u8 {
        const name_cpy = try allocator.dupe(u8, name);
        std.mem.replaceScalar(u8, name_cpy, ' ', '-');
        return std.ascii.allocLowerString(allocator, name_cpy);
    }

    pub fn preImage(self: @This()) []const u8 {
        return self.uri_path;
    }

    pub fn fromFile(dir: std.fs.Dir, path: []const u8, a: std.mem.Allocator) anyerror!@This() {
        const map = StaticBlogDataHandle.INFO_MAP;
        const info = map.get(path) orelse return error.NoMetadata;

        const file = try dir.openFile(path, .{});
        defer file.close();

        var split = std.mem.splitBackwardsScalar(u8, path, '.');
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
            .last_modified = info.last_modified,
            .created = info.created,
            .uri_path = uri_path,
            .file_name = file_name,
            .name = post_name,
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
    var newest_blog_post: ?*BlogPostInfo = null;
    while (iter.next()) |n| {
        if (newest_blog_post) |p| {
            if (n.created > p.*.created) newest_blog_post = n;
        } else newest_blog_post = n;
    }

    default_blog_path = newest_blog_post.?.uri_path;
    return default_blog_path.?;
}

/// returned blog page needs to be freed
fn getBlogPage(allocator: std.mem.Allocator, postpath: []const u8) !?CurrentBlogPage {
    try BlogDirectory.tryUpdate();
    const all_posts = BlogDirectory.get().map;

    const post = all_posts.get(std.hash_map.hashString(postpath)) orelse {
        log.err("the name {s} does not have an associated post\n", .{postpath});
        return error.NotFound;
    };

    var iter = all_posts.valueIterator();
    const blogs_data = try allocator.alloc(ClientsideBlogData, all_posts.count());
    var i: usize = 0;
    while (iter.next()) |p| : (i += 1) {
        blogs_data[i] = .{
            .last_modified = p.last_modified,
            .created = p.created,
            .name = p.name,
            .uri_path = p.uri_path,
        };
    }
    std.mem.sort(ClientsideBlogData, blogs_data, .{}, struct {
        fn lt(_: @TypeOf(.{}), this: ClientsideBlogData, other: ClientsideBlogData) bool {
            return (this.created > other.created);
        }
    }.lt);

    log.debug(
        \\POST:
        \\  NAME: {s}
        \\  FileName: {s}
    , .{ post.name, post.file_name });

    return CurrentBlogPage{
        .path = post.uri_path,
        .name = post.name,
        .filename = post.file_name,
        .last_modified = post.last_modified,
        .created = post.created,
        .all_blogs = blogs_data,
    };
}

pub fn blogHandler(_: *StaticBlogDataHandle, a: std.mem.Allocator, r: Request, w: *std.Io.Writer) anyerror!void {
    const parts = zyph.parseRequestParts(&r);

    const postpath: []const u8 = blk: {
        if (parts.query) |query| {
            log.debug("QUERY: {s}", .{query});
            var split = std.mem.splitBackwardsSequence(u8, query, "post=");
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
        return error.Redirect;
    }

    var t = try zemplate.Template(CurrentBlogPage).init(
        a,
        blog,
    );
    defer t.deinit();

    const body = t.render(@embedFile("blog.html"), .{}) catch |err| {
        std.debug.panic("Failed to render template: {}", .{err});
    };

    try w.writeAll(body);
}
