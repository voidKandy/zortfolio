const std = @import("std");
const ArrayList = std.ArrayList;

const TokenType = enum {
    Block,
    MarkerOpen,
    MarkerClose,
    Access,
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

const Lexer = struct {
    const Self = @This();
    input: []const u8,
    pos: usize,
    const MARKER_OPEN: []const u8 = "||zz";
    const MARKER_CLOSE: []const u8 = "zz||";

    fn init(input: []const u8) Self {
        const l = Lexer{
            .input = input,
            .pos = 0,
        };
        return l;
    }

    fn debug(l: *Self) void {
        std.log.warn("lexer:\nposition: {d}\nnext_position: {d}\nchar: {c}\ninput: {s}\n", .{ l.pos, l.next_pos, l.ch, l.input });
    }

    /// Move forward by one byte
    /// returns current char
    fn progress(self: *Self) ?u8 {
        if (self.pos >= self.input.len) {
            return null;
        }
        const ret = self.input[self.pos];
        self.pos += 1;
        return ret;
    }

    /// returns an optional pointer to the next char
    fn peek_next(self: *Self) ?*const u8 {
        if (self.pos >= self.input.len) {
            return null;
        }
        return &self.input[self.pos];
    }

    /// Progresses through input, outputting the head of a linked list of tokens
    fn process_input(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !Tokens {
        var tokens = Tokens{ .first = null };
        var buffer = ArrayList(u8).init(allocator);
        defer buffer.deinit();

        var prev_token: ?*const TokenType = null;
        var current_byte: ?u8 = null;

        outer: while (self.progress()) |c| {
            try buffer.append(c);
            current_byte = c;

            switch (c) {
                MARKER_OPEN[0] => {
                    for (1..MARKER_OPEN.len) |i| {
                        if (self.peek_next().?.* == MARKER_OPEN[i]) {
                            current_byte = self.progress();
                            try buffer.append(current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (0..MARKER_OPEN.len) |_| {
                        _ = buffer.pop();
                    }

                    var block_token = try Token.from_array_list(&buffer, TokenType.Block);
                    // std.log.warn("adding token with content: {s}\n", .{block_token.content});
                    tokens.prepend(try block_token.into_node(allocator));

                    var marker_token = try Token.from_const_array(MARKER_OPEN, TokenType.MarkerOpen, allocator);
                    // std.log.warn("Adding open marker token\n", .{});
                    prev_token = &marker_token.typ;
                    tokens.prepend(try marker_token.into_node(allocator));
                    // current_byte = self.progress();
                },

                MARKER_CLOSE[0] => {
                    for (1..MARKER_CLOSE.len) |i| {
                        if (self.peek_next().?.* == MARKER_CLOSE[i]) {
                            current_byte = self.progress();
                            try buffer.append(current_byte.?);
                        } else {
                            continue :outer;
                        }
                    }

                    for (0..MARKER_CLOSE.len) |_| {
                        _ = buffer.pop();
                    }

                    const typ = blk: {
                        if (prev_token) |t| {
                            if (t.* == TokenType.MarkerOpen) {
                                break :blk TokenType.Access;
                            }
                        }
                        break :blk TokenType.Block;
                    };
                    var token = try Token.from_array_list(&buffer, typ);
                    // std.log.warn("adding token with content: {s}\n", .{token.content});
                    tokens.prepend(try token.into_node(allocator));

                    var marker_token = try Token.from_const_array(MARKER_CLOSE, TokenType.MarkerClose, allocator);
                    // std.log.warn("adding marker close\n", .{});
                    prev_token = &marker_token.typ;
                    tokens.prepend(try marker_token.into_node(allocator));
                },
                else => {
                    // std.log.warn("matches none\nbuffer: [{s}]\n", .{buffer.items});
                },
            }
        }

        if (buffer.items.len > 0) {
            const typ = blk: {
                if (prev_token) |t| {
                    if (t.* == TokenType.MarkerOpen) {
                        break :blk TokenType.Access;
                    }
                }
                break :blk TokenType.Block;
            };
            var token = try Token.from_array_list(&buffer, typ);
            // std.log.warn("adding final token with content: {s}\n", .{token.content});
            tokens.prepend(try token.into_node(allocator));
        }

        return tokens;
    }
};

/// This is the Template struct
/// It contains everything you need for rendering a piece of HTML
pub fn Template(
    comptime BufferSize: usize,
    /// The type to be used to render the template
    /// + All of it's fields must be []u8
    comptime Context: type,
    /// the path of the file can be known at compile time
    /// and so too can it's contents
    comptime Path: []const u8,
) type {
    const TemplateFileContent = @embedFile(Path);
    const ContextInfo = @typeInfo(Context);

    return struct {
        const Self = @This();
        context: Context,
        allocator: std.mem.Allocator,

        const Error = error{};

        pub fn init(ctx: Context, allocator: std.mem.Allocator) !Self {
            return .{
                .context = ctx,
                .allocator = allocator,
            };
        }

        fn access_field(
            comptime fieldname: []const u8,
            allocator: std.mem.Allocator,
            ctx: Context,
        ) ![]u8 {
            const field = @field(ctx, fieldname);
            const T = @TypeOf(field);
            switch (T) {
                []u8 => return field,
                ArrayList(u8) => {
                    const copy = try allocator.dupe(u8, field.items);
                    return copy;
                },
                []const u8 => {},
                else => {
                    return error.InaccesibleType;
                },
            }
            var buf: []u8 = try allocator.alloc(u8, field.len);

            for (field, 0..) |byte, i| {
                buf[i] = byte;
            }
            return buf;
        }

        pub fn render(self: *Self) !ArrayList(u8) {
            var buffer = ArrayList(u8).init(self.allocator);
            var lexer = Lexer.init(TemplateFileContent[0..]);
            var tokens: Tokens = try lexer.process_input(self.allocator);

            while (tokens.pop()) |t| {
                defer self.allocator.destroy(t);
                defer self.allocator.free(t.data.content);
                switch (t.data.typ) {
                    TokenType.Block => {
                        try buffer.appendSlice(t.data.content);
                    },
                    TokenType.Access => {
                        var alloc_buffer: [BufferSize]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&alloc_buffer);
                        const allocator = fba.allocator();

                        const lookup = std.mem.trim(u8, t.data.content, "\n .");
                        std.log.warn("trying lookup: [{s}]\n", .{lookup});

                        inline for (ContextInfo.Struct.fields) |f| {
                            if (std.mem.eql(u8, f.name, lookup)) {
                                const val = try Self.access_field(f.name, allocator, self.context);
                                defer allocator.free(val);

                                try buffer.appendSlice(val);
                            }
                        }
                    },
                    else => {},
                }
            }
            return buffer;
        }
    };
}

const Test = struct { field: []const u8, attr: []const u8 };
const TestTemplate = Template(2048, Test, "test/test.html");
test "render test" {
    const allocator = std.testing.allocator;
    var template = try TestTemplate.init(Test{ .field = "mom", .attr = "this-attr" }, allocator);
    const expected =
        \\<div>
        \\  mom
        \\  <div attribute="this-attr">
        \\  </div>
    ;

    const render = try template.render();
    defer render.deinit();

    if (!std.mem.eql(u8, expected, render.items)) {
        std.debug.panic("did not get expected render!\nExpected: {s}\ngot: {s}\n", .{ expected, render.items });
    }
}

// This test causes memory errors, but lexing works otherwise
test "lexing test" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const content = @embedFile("test/test.html");
    var lexer = Lexer.init(content[0..]);
    var tokens = try lexer.process_input(arena.allocator());

    const expected: [9]struct { content: []const u8, typ: TokenType } = .{ .{
        .content = "<div>",
        .typ = TokenType.Block,
    }, .{
        .content = "||zz",
        .typ = TokenType.MarkerOpen,
    }, .{
        .content = ".field",
        .typ = TokenType.Access,
    }, .{
        .content = "zz||",
        .typ = TokenType.MarkerClose,
    }, .{
        .content = "<div attribute=\"",
        .typ = TokenType.Block,
    }, .{
        .content = "||zz",
        .typ = TokenType.MarkerOpen,
    }, .{
        .content = ".attr",
        .typ = TokenType.Access,
    }, .{
        .content = "zz||",
        .typ = TokenType.MarkerClose,
    }, .{
        .content = "\"></div>",
        .typ = TokenType.Block,
    } };

    var i: usize = 0;
    while (tokens.pop()) |t| : (i += 1) {
        const trimmed_ex = std.mem.trim(u8, expected[i].content, " \n");
        const trimmed_got = std.mem.trim(u8, t.data.content, " \n");
        if (!std.mem.eql(u8, trimmed_ex, trimmed_got)) {
            std.debug.panic("Trimmed incorrect!\nExpected: [{s}]\nGot: [{s}]\n", .{ trimmed_ex, trimmed_got });
        }
        if (!std.meta.eql(expected[i].typ, t.data.typ)) {
            std.debug.panic("Type incorrect!\nExpected, {any}\nGot: {any}\n", .{ expected[i].typ, t.data.typ });
        }
    }
}
