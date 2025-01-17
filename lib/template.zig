const std = @import("std");
const ArrayList = std.ArrayList;

const TokenType = enum {
    Block,
    MarkerOpen,
    MarkerClose,
    ExeString,
};

const Token = struct {
    content: []u8,
    typ: TokenType,

    fn from_array_list(list: *ArrayList(u8), typ: TokenType) !Token {
        const content = try list.toOwnedSlice();
        return .{ .content = content, .typ = typ };
    }

    fn from_const_array(array: []const u8, typ: TokenType, allocator: std.mem.Allocator) !Token {
        var arraylist = ArrayList(u8).init(allocator);
        for (array) |v| {
            try arraylist.append(v);
        }
        return Token.from_array_list(&arraylist, typ);
    }

    fn into_node(self: @This(), allocator: std.mem.Allocator) !*Tokens.Node {
        const node = try allocator.create(Tokens.Node);
        node.* = Tokens.Node{ .data = self, .next = null };
        return node;
    }
};

const Tokens = std.DoublyLinkedList(Token);

pub const Lexer = struct {
    const Self = @This();
    input: []const u8,
    pos: usize,
    const MARKER_OPEN: []const u8 = "\\\\zz";
    const MARKER_CLOSE: []const u8 = "zz\\\\";

    pub fn init(input: []const u8) Self {
        const l = Lexer{
            .input = input,
            .pos = 0,
        };
        return l;
    }

    pub fn debug(l: *Self) void {
        std.log.warn("lexer:\nposition: {d}\nnext_position: {d}\nchar: {c}\ninput: {s}\n", .{ l.pos, l.next_pos, l.ch, l.input });
    }

    /// Move forward by one byte
    /// returns current char
    pub fn progress(self: *Self) ?u8 {
        if (self.pos >= self.input.len) {
            return null;
        }
        const ret = self.input[self.pos];
        self.pos += 1;
        return ret;
    }

    /// returns an optional pointer to the next char
    pub fn peek_next(self: *Self) ?*const u8 {
        if (self.pos + 1 >= self.input.len) {
            return null;
        }
        return &self.input[self.pos + 1];
    }

    /// Progresses through input, outputting the head of a linked list of tokens
    pub fn process_input(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !Tokens {
        var tokens = Tokens{ .first = null };
        var buffer = ArrayList(u8).init(allocator);
        defer buffer.deinit();

        var prev_token: ?*const TokenType = null;
        var current_byte: ?u8 = null;

        outer: while (self.progress()) |c| {
            std.log.warn("current: {c}\n", .{c});
            try buffer.append(c);
            current_byte = c;

            const next = self.peek_next() orelse break;
            switch (next.*) {
                MARKER_OPEN[0] => {
                    std.log.warn("matches marker open\n", .{});
                    current_byte = self.progress();
                    for (1..MARKER_OPEN.len) |i| {
                        if (self.peek_next().?.* == MARKER_OPEN[i]) {
                            current_byte = self.progress();
                            try buffer.append(current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (1..MARKER_OPEN.len) |_| {
                        _ = buffer.pop();
                    }

                    var block_token = try Token.from_array_list(&buffer, TokenType.Block);
                    std.log.warn("adding token with content: {s}\n", .{block_token.content});
                    tokens.prepend(try block_token.into_node(allocator));

                    var marker_token = try Token.from_const_array(MARKER_OPEN, TokenType.MarkerOpen, allocator);
                    std.log.warn("Adding open marker token\n", .{});
                    prev_token = &marker_token.typ;
                    tokens.prepend(try marker_token.into_node(allocator));
                    current_byte = self.progress();
                },

                MARKER_CLOSE[0] => {
                    std.log.warn("matches marker close", .{});
                    current_byte = self.progress();
                    for (1..MARKER_CLOSE.len) |i| {
                        std.log.warn("got: {c}, expecting {c}\n", .{ self.peek_next().?.*, MARKER_CLOSE[i] });
                        if (self.peek_next().?.* == MARKER_CLOSE[i]) {
                            current_byte = self.progress();
                            try buffer.append(current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (1..MARKER_CLOSE.len) |_| {
                        _ = buffer.pop();
                    }

                    const typ = blk: {
                        if (prev_token) |t| {
                            if (t.* == TokenType.MarkerOpen) {
                                break :blk TokenType.ExeString;
                            }
                        }
                        break :blk TokenType.Block;
                    };
                    var token = try Token.from_array_list(&buffer, typ);
                    std.log.warn("adding token with content: {s}\n", .{token.content});
                    tokens.prepend(try token.into_node(allocator));

                    var marker_token = try Token.from_const_array(MARKER_CLOSE, TokenType.MarkerClose, allocator);
                    std.log.warn("adding marker close\n", .{});
                    prev_token = &marker_token.typ;
                    tokens.prepend(try marker_token.into_node(allocator));
                    current_byte = self.progress();
                },
                else => {
                    std.log.warn("matches none\nbuffer: [{s}]\n", .{buffer.items});
                },
            }
        }

        if (buffer.items.len > 0) {
            const typ = blk: {
                if (prev_token) |t| {
                    if (t.* == TokenType.MarkerOpen) {
                        break :blk TokenType.ExeString;
                    }
                }
                break :blk TokenType.Block;
            };
            var token = try Token.from_array_list(&buffer, typ);
            std.log.warn("adding final token with content: {s}\n", .{token.content});
            tokens.prepend(try token.into_node(allocator));
        }

        return tokens;
    }
};

/// This is the Template struct
/// It contains everything you need for rendering a piece of HTML
fn Template(
    comptime Context: type,
    /// the path of the file can be known at compile time
    /// and so too can it's contents
    comptime Path: []const u8,
) type {
    const FileSize: comptime_int = @as(comptime_int, @embedFile(Path).len);

    return struct {
        const Self = @This();
        context: Context,
        content: *const [FileSize:0]u8,
        allocator: std.mem.Allocator,

        const Error = error{};

        fn init(ctx: Context, allocator: std.mem.Allocator) !Self {
            const file_content = @embedFile(Path);
            return .{
                .context = ctx,
                .content = file_content,
                .allocator = allocator,
            };
        }

        fn render(self: *Self) !ArrayList(u8) {
            var buffer = ArrayList(u8).init(self.allocator);
            var lexer = Lexer.init(self.content[0..]);
            var tokens: Tokens = try lexer.process_input(self.allocator);

            while (tokens.pop()) |t| {
                defer self.allocator.destroy(t);
                defer self.allocator.free(t.data.content);
                switch (t.data.typ) {
                    TokenType.Block => {
                        try buffer.appendSlice(t.data.content);
                    },
                    TokenType.ExeString => {
                        // const execute = try access(&self.context, t.data);
                        // try buffer.appendSlice(execute);
                    },
                    else => {},
                }
            }
            return buffer;
        }

        fn access(ctx: *Context, token: Token) ![]u8 {
            if (token.typ == TokenType.ExeString) {
                const info = @typeInfo(Context);
                inline for (info.Struct.fields) |f| {
                    const is = std.mem.eql(u8, f.name, token.content[2..]);
                    std.log.warn("{s} and {s} are equal: {any}\n", .{ f.name, token.content[2..], is });
                    _ = @field(ctx, f.name);
                }
                var buffer: [1000]u8 = undefined;
                const mutableSlice: []u8 = buffer[0..9];
                std.mem.copyForwards(u8, mutableSlice, " Content ");
                return mutableSlice;
            } else {
                return error.NotFound;
            }
        }
    };
}
const Test = struct { field: u8 };
const TestTemplate = Template(Test, "test/test.html");
test "read test" {
    const allocator = std.testing.allocator;
    var template = try TestTemplate.init(Test{ .field = 8 }, allocator);

    const render = try template.render();
    defer render.deinit();

    std.log.warn("got render: {s}\n", .{render.items});
}
