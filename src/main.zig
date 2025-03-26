const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
pub const routes = @import("routes.zig");
const music = @import("music.zig");
const middleware = @import("middleware.zig");

// just a way to share our allocator via callback
pub const SharedAllocator = struct {
    // static
    var allocator: std.mem.Allocator = undefined;

    const Self = @This();

    // just a convenience function
    pub fn init(a: std.mem.Allocator) void {
        allocator = a;
    }

    // static function we can pass to the listener later
    pub fn getAllocator() std.mem.Allocator {
        return allocator;
    }
};

fn not_found_handler(r: zap.Request) void {
    r.setStatus(zap.StatusCode.not_found);

    const body = "<html><body><h1>404 NOT FOUND</h1></body></html>";
    _ = r.sendBody(body) catch |err| {
        std.debug.print("Error sending response: {any}\n", .{err});
    };
}

fn on_request_verbose(r: zap.Request) void {
    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }
    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}

// pub fn HydratedTemplate(Template: anytype) type {
//     return struct {
//         template: Template,
//         const Self = @This();

//         pub fn from(template: Template) Self {
//             return Self{ .template = template };
//         }

//         pub fn on_req(self: *Self, r: zap.Request) void {
//             var body = self.template.render() catch |err| {
//                 std.debug.panic("Failed to render template: {any}", .{err});
//             };

//             defer body.deinit();

//             hydrate_components(&body) catch |err| {
//                 std.log.err("Failed to hydrate template: {any}", .{err});
//                 return;
//             };

//             r.sendBody(body.items) catch |e| {
//                 std.log.err("Failed to send body template: {}", .{e});
//                 return;
//             };
//         }
//     };
// }

// fn hydrate_components(body: *std.ArrayList(u8)) !void {
//     const allocator = SharedAllocator.getAllocator();
//     const needed_components = routes.parse_for_needed_components(allocator, body.items) catch |e| {
//         std.log.err("failed to parse for needed components body: {}\n", .{e});
//         return;
//     };

//     for (needed_components) |opt| {
//         const content = opt orelse break;
//         body.appendSlice(content) catch |e| {
//             std.log.err("failed to append component body to buffer: {}\n", .{e});
//             return;
//         };
//     }
// }

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();
    SharedAllocator.init(allocator);
    var component_cache = try routes.init_component_cache(allocator, "components");
    defer component_cache.deinit();
    // const cached_components_content = try middleware.CachedComponentsContent.create(allocator, component_cache);
    // defer cached_components_content.deinit();
    // middleware.CachedComponentsContent.init(cached_components_content);

    const env_map = try std.process.getEnvMap(allocator);

    const port_str = env_map.get("PORT") orelse "3000";
    const port = try std.fmt.parseInt(usize, port_str, 10);

    var router = zap.Router.init(allocator, .{ .not_found = not_found_handler });
    defer router.deinit();

    var music_info = try music.MusicInfo.build(allocator);
    defer music_info.deinit();
    var mtmp = try music.MusicTemplate.init(music_info, allocator);
    var home = try routes.HomeTemplate.init(routes.Home{}, allocator);
    var info = try routes.InfoTemplate.init(routes.Info{}, allocator);

    try router.handle_func_unbound("/", on_request_verbose);
    try router.handle_func("/Home", &home, &routes.home_handler);
    try router.handle_func("/Music", &mtmp, &music.music_handler);
    try router.handle_func("/Info", &info, &routes.info_handler);

    var htmlHandler = try middleware.HtmlEndpoint.init(&router, component_cache, null);

    var hydrationHandler = middleware.HydrationMiddleware.init(htmlHandler.getHandler());

    var listener = try zap.Middleware.Listener(middleware.HydrationContext).init(
        .{
            .on_request = null, // must be null for middleware
            .public_folder = "serve",
            .port = port,
            .log = true,
            .max_clients = 100000,
        },
        hydrationHandler.getHandler(),
        SharedAllocator.getAllocator,
    );
    zap.enableDebugLog();
    listener.listen() catch |err| {
        std.debug.print("\nLISTEN ERROR: {any}\n", .{err});
        return;
    };

    std.debug.print("TCP Listener is running\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}

test {
    std.testing.refAllDecls(@This());
}
