const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;
const ArrayList = std.ArrayList;

pub const Route = enum {
    Home,
    About,

    const RouteError = error{
        EmptyPath,
        NotFound,
    };

    pub const HandlerFn = fn (segments: *Segments, r: zap.Request) void;

    pub fn to_string(self: Route) []const u8 {
        return switch (self) {
            .Home => "home",
            .About => "about",
        };
    }

    /// Consumes the first segment to find a route, returns the route fn associated with the given route
    pub fn handler(segments: *Segments) *const HandlerFn {
        const first_seg = segments.popFirst() orelse return not_found_handler;

        const route = route: {
            if (std.mem.eql(u8, first_seg.data.items, Route.Home.to_string())) {
                break :route Route.Home;
            }
            if (std.mem.eql(u8, first_seg.data.items, Route.About.to_string())) {
                break :route Route.About;
            }
            return not_found_handler;
        };

        return switch (route) {
            .Home => home_handler,
            .About => about_handler,
        };
    }
};

fn not_found_handler(segments: *Segments, r: zap.Request) void {
    print("hello from home!\n", .{});
    _ = segments;
    r.setStatus(zap.StatusCode.not_found);
    r.sendBody("<html><body><h1>404 NOT FOUND</h1></body></html>") catch return;
}

fn home_handler(segments: *Segments, r: zap.Request) void {
    print("hello from home!\n", .{});
    _ = segments;
    r.sendBody("<html><body><h1>HOME</h1></body></html>") catch return;
}

fn about_handler(segments: *Segments, r: zap.Request) void {
    print("hello from about!\n", .{});
    _ = segments;
    r.sendBody("<html><body><h1>ABOUT</h1></body></html>") catch return;
}

pub const Segments = std.SinglyLinkedList(ArrayList(u8));
pub const SegmentsNode = std.SinglyLinkedList(ArrayList(u8)).Node;
pub fn parse_path(path: []const u8, allocator: std.mem.Allocator) !Segments {
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
