const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;
const ArrayList = std.ArrayList;

pub fn handle_request(r: zap.Request) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var segments = parse_path(r.path orelse Route.Home.to_string(), allocator) catch |err| {
        std.debug.panic("failed to parse segments: {any}", .{err});
    };

    const handler_fn = Route.match_segments_to_handler(&segments);
    handler_fn(allocator, &segments, r);

    return;
}

// const FILE_READ_BUFFER_SIZE = 2048;

pub const Route = enum {
    Home,
    About,
    Settings,

    const RouteError = error{
        EmptyPath,
        NotFound,
    };

    // Make sure to have each of these passed as `routes` for the `routes-nav` component
    fn to_string(self: Route) []const u8 {
        return switch (self) {
            .Home => "home",
            .About => "about",
            .Settings => "settings",
        };
    }

    /// Consumes the first segment to find a route, returns the route fn associated with the given route
    fn match_segments_to_handler(segments: *Segments) *const HandlerFn {
        const first_seg = segments.first orelse return not_found_handler;
        const route = route: {
            const str = first_seg.data.items;
            std.log.debug("checking route for: {s}", .{str});
            if (std.mem.eql(u8, str, Route.Home.to_string())) {
                break :route Route.Home;
            }
            if (std.mem.eql(u8, str, Route.About.to_string())) {
                break :route Route.About;
            }
            if (std.mem.eql(u8, str, Route.Settings.to_string())) {
                break :route Route.Settings;
            }
            return not_found_handler;
        };

        return switch (route) {
            .Home => home_handler,
            .About => about_handler,
            .Settings => settings_handler,
        };
    }
};

fn read_route_file(allocator: std.mem.Allocator, segments: *Segments) ![]u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "serve/pages/{s}.html",
        .{segments.first.?.data.items},
    );
    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 2048);

    return contents;
}

const HandlerFn = fn (allocator: std.mem.Allocator, segments: *Segments, r: zap.Request) void;
fn not_found_handler(allocator: std.mem.Allocator, segments: *Segments, r: zap.Request) void {
    _ = segments;
    _ = allocator;

    r.setStatus(zap.StatusCode.not_found);

    const body = "<html><body><h1>404 NOT FOUND</h1></body></html>";
    _ = r.sendBody(body) catch |err| {
        std.debug.print("Error sending response: {any}\n", .{err});
    };
}

fn home_handler(allocator: std.mem.Allocator, segments: *Segments, r: zap.Request) void {
    const body = read_route_file(allocator, segments) catch |err| {
        std.debug.panic("failed to read route file: {any}\n", .{err});
    };
    r.sendBody(body) catch return;
}

fn settings_handler(allocator: std.mem.Allocator, segments: *Segments, r: zap.Request) void {
    const body = read_route_file(allocator, segments) catch |err| {
        std.debug.panic("failed to read route file: {any}\n", .{err});
    };
    r.sendBody(body) catch return;
}

fn about_handler(allocator: std.mem.Allocator, segments: *Segments, r: zap.Request) void {
    print("hello from about!\n", .{});
    _ = segments;
    _ = allocator;
    r.sendBody("<html><body><h1>ABOUT</h1></body></html>") catch return;
}

const Segments = std.SinglyLinkedList(ArrayList(u8));
const SegmentsNode = std.SinglyLinkedList(ArrayList(u8)).Node;
fn parse_path(path: []const u8, allocator: std.mem.Allocator) std.mem.Allocator.Error!Segments {
    var segments = Segments{ .first = null };
    var current = ArrayList(u8).init(allocator);
    var head: ?*SegmentsNode = null;

    for (path) |char| {
        switch (char) {
            '/' => {
                if (current.items.len != 0) {
                    const new = ArrayList(u8).fromOwnedSlice(allocator, try current.toOwnedSlice());
                    const node = try allocator.create(SegmentsNode);
                    node.* = SegmentsNode{ .data = new, .next = null };

                    if (head) |h| {
                        h.findLast().insertAfter(node);
                    } else {
                        std.log.warn("set head\n", .{});
                        head = node;
                        segments.prepend(head.?);
                    }
                }
            },
            else => {
                try current.append(char);
            },
        }
    }

    if (current.items.len != 0) {
        const new = ArrayList(u8).fromOwnedSlice(allocator, try current.toOwnedSlice());
        const node = try allocator.create(SegmentsNode);
        node.* = SegmentsNode{ .data = new, .next = null };

        if (head) |h| {
            h.findLast().insertAfter(node);
        } else {
            head = node;
            segments.prepend(head.?);
        }
    }

    return segments;
}

test "path parsing" {
    const path = "/this/is/a/path";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var segments = try parse_path(path, allocator);

    const all_expected: []const []const u8 = &.{
        "this",
        "is",
        "a",
        "path",
    };

    var i: u8 = 0;
    const head = segments.popFirst() orelse std.debug.panic("segments should have head", .{});
    var current = head;

    while (current.next) |n| : (i += 1) {
        const seg = current.data;
        for (seg.items, 0..) |ch, k| {
            if (ch != all_expected[i][k]) {
                std.debug.panic("expected to get {c} found {c}\n", .{ all_expected[i][k], ch });
            }
        }
        current = n;
    }
    print("Passed!", .{});
}
