const std = @import("std");
const log = std.log.scoped(.BlogsMetadata);

const BLOG_DIR = "blog";
const Metadata = struct {
    path: []const u8,
    last_modified: i64,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(BLOG_DIR, .{ .iterate = true });
    var it = dir.iterate();

    var files = try std.ArrayList(Metadata).initCapacity(arena, 2048);

    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (entry.name[0] == '.') continue;

        const stat = try dir.statFile(entry.name);
        log.warn("{s}\n", .{entry.name});
        try files.append(arena, Metadata{
            .path = entry.name,
            .last_modified = @as(i64, @intCast(stat.mtime)),
        });
    }

    // Serialize once into a dynamic buffer
    var out: std.io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(files.items, .{ .whitespace = .indent_2 }, &out.writer);

    const json_bytes = out.toOwnedSlice() catch @panic("out of memory");

    const outfile =
        "blogsMetadata.json";
    const realpath = try std.fs.cwd().realpathAlloc(arena, outfile);
    var file = try std.fs.cwd().createFile(outfile, .{});
    log.warn(
        \\ Writing to file: {s}
    , .{realpath});
    defer file.close();
    try file.writeAll(json_bytes);
}
