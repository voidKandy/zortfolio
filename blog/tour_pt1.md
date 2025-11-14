# Source Code Tour Pt.1
> A tour of the build system 

Today I figured I would start the tour of the source code of this site with the primary building block of the application: `build.zig`.

## `build.zig`
My build is pretty standard, so I'm not going to share the whole file, instead I will just share the out of the ordinary steps.
The first is a function I wrote that sources from a `.env` file, and the other is a combination of a tool and a few lines that expose a `.json` file to my program.

### `.env` Sourcing
 `.env` files are generally used to configure the environment of a given application. Generally speaking they are hidden from git or whichever version control system a dev might use. This way "secrets" can live in these `.env` files (such as API keys or other sensitive info) and only the program can actually look into their values at runtime.
Before, I was using [`zdotenv`](https://github.com/BitlyTwiser/zdotenv), but I've been trying to minimize dependencies and I though it would be fun to try to build `.env` sourcing into the build system. 
#### The code
```zig
fn loadDotEnv(run: *std.Build.Step.Run) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env_file = std.fs.cwd().openFile(".env", .{}) catch |e| {
            switch (e) {
                error.FileNotFound => {
                    log.info(
                        \\ No .env file found
                    , .{});
                },
                else => {
                    log.err(
                        \\ build.zig could not open .env file: {any}
                    , .{e});
                },
            }
            return;
    };

    defer env_file.close();

    const read_buffer = arena.alloc(u8, 2048) catch @panic("out of memory");
    var reader = env_file.reader(read_buffer);

    const contents = reader.interface.allocRemaining(arena, .unlimited) catch @panic("failed to read");

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            var parts = std.mem.splitScalar(u8, trimmed, '=');

            const key = parts.first();
            const value = std.mem.trim(u8, parts.rest(), " \"");

            run.setEnvironmentVariable(key, value);
    }
}
```
So the function is pretty simple; It takes a `Run` step (which is basically just a binary that will be built), looks for a `.env` file, if it finds one it parses it and sets environment variables specifically for that `Run` step. This way the environment variables in the `.env` file will be accessible to the program run by that `Run` step just like they would be if any other `.env` library was used.
### Blog post metadata
Notice the section at the top of this page that tells you when this post was last edited? That was trickier to implement than you would think. It's easy enough to embed that information in my local environment, but when I ship the source code of this website to a docker container to be run in a server I'm renting, all of the source code gets copied, and the last modified time of all files gets set to the time that they were copied. If I hadn't implemented this step, every blog post would have the same last modified time. Basically, I've added a build step that reads the `blogs` directory and creates a `JSON` map of all the blog posts and their *true* last updated time. This step runs in a GitHub action that will update the `json` file anytime a new blog post is either added to the repo or changed. Then, when I parse through my blog posts to actually present them I reference the generated `JSON` file to get the true last updated time, rather than the blog post's file's last updated time.
### The code
I have one file that is actually run by github actions on commits containing changes to the blog directory: 
```zig
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
            log.warn("{s} : {d}\n", .{ entry.name, stat.mtime });
            try files.append(arena, Metadata{
                .path = entry.name,
                .last_modified = @as(i64, @intCast(stat.mtime)),
            });
    }
    var out: std.io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(files.items, .{ .whitespace = .indent_2 }, &out.writer);

    const json_bytes = out.toOwnedSlice() catch @panic("out of memory");

    const outfile = "blogsMetadata.json";
    var file = try std.fs.cwd().createFile(outfile, .{});
    const realpath = try std.fs.cwd().realpathAlloc(arena, outfile);
    log.warn(
            \\ Writing to file: {s}
    , .{realpath});
    defer file.close();
    try file.writeAll(json_bytes);
}
```
It may seem like overkill, and maybe it is but I personally really like having the dates for my blog posts. Thanks for reading this post, next week I plan on going over the frontend.
