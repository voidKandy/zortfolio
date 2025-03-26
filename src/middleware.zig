const std = @import("std");
const root = @import("root");
const zap = @import("zap");
const zemplate = @import("zemplate");

const HydrationInfo = struct {
    path: []const u8 = undefined,
    query: []const u8 = undefined,
};

const HydrationTemplateInfo = struct {
    path: []const u8 = "/",
    query: []const u8 = "",
    components: []u8,
};

// create a combined context struct
// NOTE: context struct members need to be optionals which default to null!!!
pub const HydrationContext =
    struct {
    hydration: ?HydrationInfo = null,
    // cache: ?ComponentCache(u32, "components") = null,
};

const HydrationTemplate = zemplate.template.Template(HydrationTemplateInfo, @embedFile("pages/index.html"));
// we create a Handler type based on our Context
const Handler = zap.Middleware.Handler(HydrationContext);
pub const HydrationMiddleware = struct {
    handler: Handler,

    const Self = @This();

    pub fn init(other: ?*Handler) Self {
        return .{
            .handler = Handler.init(onRequest, other),
        };
    }

    pub fn getHandler(self: *Self) *Handler {
        return &self.handler;
    }

    pub fn onRequest(handler: *Handler, r: zap.Request, context: *HydrationContext) bool {
        const self: *Self = @fieldParentPtr("handler", handler);
        _ = self;

        // We dont need to hydrate the page if the req came through htmx
        if (r.getHeader("hx-request") == null) {
            context.hydration = HydrationInfo{
                .path = r.path orelse "/",
                .query = r.query orelse "/",
            };

            std.log.debug("\n\nHydration middleware set context!\nPath: {s}\nQuery: {s}\n", .{ context.hydration.?.path, context.hydration.?.query });
        }

        return handler.handleOther(r, context);
    }
};

pub const HtmlEndpoint = struct {
    handler: Handler,
    router: *zap.Router,
    components: std.ArrayList(u8),
    const Self = @This();

    pub fn init(router: *zap.Router, component_cache: root.routes.ComponentCache, other: ?*Handler) !Self {
        const allocator = root.SharedAllocator.getAllocator();
        var components = std.ArrayList(u8).init(allocator);
        var iter = component_cache.valueIterator();
        while (iter.next()) |v| {
            try components.appendSlice(v.content);
        }
        return .{ .router = router, .components = components, .handler = Handler.init(onRequest, other) };
    }

    pub fn getHandler(self: *Self) *Handler {
        return &self.handler;
    }

    pub fn onRequest(handler: *Handler, r: zap.Request, context: *HydrationContext) bool {
        const self: *Self = @fieldParentPtr("handler", handler);

        const allocator = root.SharedAllocator.getAllocator();
        const components_copy = allocator.dupe(u8, self.components.items) catch |e| {
            std.log.err("failed to dupe components: {}\n", .{e});
            return false;
        };
        var template_info = HydrationTemplateInfo{
            .components = components_copy,
        };
        if (context.hydration) |h| {
            template_info.path = h.path;
            template_info.query = h.query;
            var tmp = HydrationTemplate.init(template_info, allocator) catch unreachable;
            std.debug.assert(r.isFinished() == false);

            const render = tmp.render() catch unreachable;
            defer render.deinit();
            // std.log.warn("Path: {s}\nQuery: {s}", .{
            //     h.path,
            //     h.query,
            // });
            r.sendBody(render.items) catch unreachable;
            std.debug.assert(r.isFinished() == true);
            return true;
        }

        const func = self.router.*.on_request_handler();
        func(r);

        return true;
    }
};
