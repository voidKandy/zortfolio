const std = @import("std");
const zap = @import("zap");
const template = @import("template.zig");
const routes = @import("routes.zig");
const music = @import("music.zig");

pub const HydrationTemplate = template.Template(HydrationMiddleware.HydrationInfo, "pages/index.html");
// just a way to share our allocator via callback
const SharedAllocator = struct {
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

// create a combined context struct
// NOTE: context struct members need to be optionals which default to null!!!
const Context = struct {
    hydration: ?HydrationMiddleware.HydrationInfo = null,
};

// we create a Handler type based on our Context
const Handler = zap.Middleware.Handler(Context);

const HydrationMiddleware = struct {
    handler: Handler,

    const Self = @This();

    const HydrationInfo = struct {
        path: []const u8 = undefined,
        query: []const u8 = undefined,
    };

    pub fn init(other: ?*Handler) Self {
        return .{
            .handler = Handler.init(onRequest, other),
        };
    }

    pub fn getHandler(self: *Self) *Handler {
        return &self.handler;
    }

    pub fn onRequest(handler: *Handler, r: zap.Request, context: *Context) bool {
        const self: *Self = @fieldParentPtr("handler", handler);
        _ = self;

        // We dont need to hydrate the page if the req came through htmx
        if (r.getHeader("hx-request") == null) {
            context.hydration = HydrationInfo{
                .path = r.path orelse "/",
                .query = r.query orelse "",
            };

            std.log.debug("\n\nHydration middleware: set context {any}\n\n", .{context.hydration});
        }

        return handler.handleOther(r, context);
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

const HtmlEndpoint = struct {
    handler: Handler,
    router: *zap.Router,
    const Self = @This();

    pub fn init(router: *zap.Router, other: ?*Handler) !Self {
        return .{ .router = router, .handler = Handler.init(onRequest, other) };
    }

    pub fn getHandler(self: *Self) *Handler {
        return &self.handler;
    }

    pub fn onRequest(handler: *Handler, r: zap.Request, context: *Context) bool {
        const self: *Self = @fieldParentPtr("handler", handler);

        const allocator = SharedAllocator.getAllocator();
        if (context.hydration) |h| {
            var tmp = HydrationTemplate.init(h, allocator) catch unreachable;
            const render = tmp.render() catch unreachable;
            std.debug.assert(r.isFinished() == false);
            std.log.warn("Path: {s}\nQuery: {s}", .{
                h.path,
                h.query,
            });
            r.sendBody(render.items) catch unreachable;
            std.debug.assert(r.isFinished() == true);
            return true;
        }

        const func = self.router.*.on_request_handler();
        func(r);

        return true;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();
    SharedAllocator.init(allocator);

    var router = zap.Router.init(allocator, .{ .not_found = not_found_handler });
    defer router.deinit();
    var home = try routes.HomeTemplate.init(routes.Home{}, allocator);
    // var about = try routes.AboutTemplate.init(routes.About{}, allocator);

    var music_info = try music.MusicInfo.build(allocator);
    std.log.warn("got music info!", .{});
    defer music_info.deinit();
    var mtmp = try music.MusicTemplate.init(music_info, allocator);

    var info = try routes.InfoTemplate.init(routes.Info{}, allocator);

    try router.handle_func_unbound("/", on_request_verbose);

    try router.handle_func("/Home", &home, &routes.home_handler);
    // try router.handle_func("/About", &about, &routes.about_handler);
    try router.handle_func("/Music", &mtmp, &music.music_handler);
    try router.handle_func("/Info", &info, &routes.info_handler);

    var htmlHandler = try HtmlEndpoint.init(&router, null);

    var hydrationHandler = HydrationMiddleware.init(htmlHandler.getHandler());

    var listener = try zap.Middleware.Listener(Context).init(
        .{
            .on_request = null, // must be null for middleware
            .public_folder = "serve",
            .port = 3000,
            .log = true,
            .max_clients = 100000,
            // .interface = "0.0.0.0",
        },
        hydrationHandler.getHandler(),
        SharedAllocator.getAllocator,
    );
    zap.enableDebugLog();
    listener.listen() catch |err| {
        std.debug.print("\nLISTEN ERROR: {any}\n", .{err});
        return;
    };

    std.debug.print("Visit me on http://127.0.0.1:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}

test {
    std.testing.refAllDecls(@This());
}
