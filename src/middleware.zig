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
                .query = r.query orelse "",
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

    pub fn init(router: *zap.Router, component_cache: ComponentCache, other: ?*Handler) !Self {
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

const ComponentCache = std.StringHashMap(ComponentInfo);
pub fn init_component_cache(a: std.mem.Allocator, parent_path: []const u8) !ComponentCache {
    var map = ComponentCache.init(a);
    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(parent_path, .{ .iterate = true });
    var iter = dir.iterate();

    while (try iter.next()) |f| {
        if (f.kind != .file) {
            continue;
        }

        const info = try ComponentInfo.new(f.name, a);
        try map.put(info.name, info);
    }

    return map;
}

const ComponentInfo = struct {
    path: []u8,
    content: []u8,
    name: []u8,

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.content);
        allocator.free(self.path);
    }

    fn new(path: []const u8, allocator: std.mem.Allocator) !@This() {
        var split = std.mem.splitBackwards(u8, path, ".");

        if (!std.mem.eql(u8, split.first(), "html")) {
            return error.NotHTML;
        }
        const filename = split.next() orelse return error.InvalidFilename;

        var uppercase_idcs: []usize = try allocator.alloc(usize, filename.len);
        var len: usize = 0;
        for (filename, 0..) |ch, i| {
            if (std.ascii.isUpper(ch)) {
                uppercase_idcs[len] = i;
                len += 1;
            }
        }
        const component_name: []u8 = try allocator.alloc(u8, filename.len + len);

        var i: usize = 0;
        for (filename) |ch| {
            if (std.ascii.isUpper(ch)) {
                component_name[i] = '-';
                i += 1;
                component_name[i] = std.ascii.toLower(ch);
            } else {
                component_name[i] = ch;
            }
            i += 1;
        }

        const fullpath = try std.fmt.allocPrint(allocator, "components/{s}", .{path});
        const file = try std.fs.cwd().openFile(fullpath, .{});
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 8092);

        return @This(){ .path = fullpath, .name = component_name, .content = content };
    }
};
