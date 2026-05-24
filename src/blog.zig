const std = @import("std");
const BlogMetadata = @import("blog_metadata").Metadata;
const ArrayList = std.ArrayList;
const Request = std.http.Server.Request;
const zemplate = @import("zemplate");
const zyph = @import("zyph");
const log = std.log.scoped(.blog);

const BlogDirectory = zyph.cache.CachedDirectory(struct {
    fn hash(fi: zyph.cache.FileItem) u64 {
        log.warn("adding entry: {s}", .{fi.relative_path[1..]});
        return std.hash_map.hashString(fi.relative_path[1..]);
    }
}.hash);

const BLOGS_PATH = "serve/blog";

pub const StaticBlogDataHandle = struct {
    /// Pulled from a file that exists at comptime
    var INFO_MAP: std.StringHashMap(struct {
        last_modified: i64,
        created: i64,
    }) = undefined;

    /// Names are always the text following the first h1(#) of a blog file
    var NAMES_MAP: std.StringHashMap([]u8) = undefined;
    /// most recently created blog
    var DEFAULT_BLOG_PATH: []const u8 = undefined;
    fn loadFromFile(a: std.mem.Allocator) !void {
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
        try loadFromFile(a);
        BlogDirectory.init(a, BLOGS_PATH);
        NAMES_MAP = .init(a);

        const all_posts = BlogDirectory.get().map;
        var iter = all_posts.valueIterator();

        var newest_blog: ?struct { []const u8, i64 } = null;
        while (iter.next()) |p| {
            const post_name: []u8 = blk: {
                var spl = std.mem.splitScalar(u8, p.content, '\n');
                const firstline = spl.first();

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

            const md = INFO_MAP.get(p.relative_path[1..]) orelse std.debug.panic(
                \\ failed to get metadata for blog post with path: {s}
            , .{p.relative_path[1..]});

            if (newest_blog) |b| {
                if (md.created > b.@"1") newest_blog = .{ p.relative_path, md.created };
            } else newest_blog = .{ p.relative_path, md.created };

            DEFAULT_BLOG_PATH = newest_blog.?.@"0"[1..];
            try NAMES_MAP.put(p.full_path, post_name);
        }

        return .{};
    }

    pub fn deinit(_: @This()) void {
        INFO_MAP.deinit();
        NAMES_MAP.deinit();
        BlogDirectory.deinit();
    }
};

pub const CurrentBlogPage = struct {
    path: []const u8,
    name: []const u8,
    filename: []const u8,
    last_modified: i128,
    created: i64,
    all_blogs: []ClientsideBlogData,
};

const ClientsideBlogData = struct {
    last_modified: i128,
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
};

/// returned blog page needs to be freed
fn getBlogPage(a: std.mem.Allocator, postpath: []const u8) !?CurrentBlogPage {
    try BlogDirectory.tryUpdate();
    const all_posts = BlogDirectory.get().map;

    const post = all_posts.get(std.hash_map.hashString(postpath)) orelse {
        log.err("the name {s} does not have an associated post\n", .{postpath});
        return error.NotFound;
    };

    var iter = all_posts.valueIterator();
    const blogs_data = try a.alloc(ClientsideBlogData, all_posts.count());
    var i: usize = 0;
    while (iter.next()) |p| : (i += 1) {
        const created = StaticBlogDataHandle.INFO_MAP.get(p.relative_path[1..]).?.created;
        const name = StaticBlogDataHandle.NAMES_MAP.get(p.full_path).?;

        blogs_data[i] = .{
            .last_modified = p.last_modified,
            .created = created,
            .name = name,
            .uri_path = p.relative_path[1..],
        };
    }
    std.mem.sort(ClientsideBlogData, blogs_data, .{}, struct {
        fn lt(_: @TypeOf(.{}), this: ClientsideBlogData, other: ClientsideBlogData) bool {
            return (this.created > other.created);
        }
    }.lt);

    // log.debug(
    //     \\POST:
    //     \\  NAME: {s}
    //     \\  FileName: {s}
    // , .{ post.name, post.file_name });

    return CurrentBlogPage{
        .path = post.relative_path[1..],
        .name = StaticBlogDataHandle.NAMES_MAP.get(post.full_path).?,
        .created = StaticBlogDataHandle.INFO_MAP.get(post.relative_path[1..]).?.created,
        .filename = post.relative_path[1..],
        .last_modified = post.last_modified,
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
            break :blk StaticBlogDataHandle.DEFAULT_BLOG_PATH;
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
            // if (zyph.getHeader(r, "x-hydrated")) |v|
            //     &.{ .{ .name = "Location", .value = redirect }, .{ .name = "x-hydrated", .value = v } }
            // else
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
