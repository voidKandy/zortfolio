const std = @import("std");
const zap = @import("zap");
const template = @import("template.zig");
const zdotenv = @import("zdotenv");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const warn = std.log.warn;

pub const Home = struct {};
pub const HomeTemplate = template.Template(Home, "pages/home.html");
pub fn home_handler(ctx: *HomeTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

pub const About = struct {};
pub const AboutTemplate = template.Template(About, "pages/about.html");
pub fn about_handler(ctx: *AboutTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

pub const Info = struct {};
pub const InfoTemplate = template.Template(Info, "pages/info.html");
pub fn info_handler(ctx: *InfoTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

pub const Music = struct {
    token: []u8,
    pub fn init(allocator: std.mem.Allocator) !Music {
        const token = try get_spotify_token(allocator);
        return Music{ .token = token };
    }

    pub fn deinit(self: Music, allocator: std.mem.Allocator) void {
        allocator.free(self.token);
    }
};
pub const MusicTemplate = template.Template(Music, "pages/music.html");
pub fn music_handler(ctx: *MusicTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    defer body.deinit();

    r.sendBody(body.items) catch return;
}

const Encoder = std.base64.standard.Encoder;
const Decoder = std.base64.standard.Decoder;
const Client = std.http.Client;

/// As per spotify's client credential flow:
/// https://developer.spotify.com/documentation/web-api/tutorials/client-credentials-flow
/// Get's token to be given to the client side to use for the musicDisplay component
fn get_spotify_token(allocator: std.mem.Allocator) ![]u8 {
    var client = Client{ .allocator = allocator };
    var env = try zdotenv.Zdotenv.init(allocator);
    try env.load();

    const env_map = try std.process.getEnvMap(allocator);

    const client_id = env_map.get("SPOTIFY_CLIENT_ID") orelse return error.NoClientId;
    const client_secret = env_map.get("SPOTIFY_CLIENT_SECRET") orelse return error.NoClientSecret;
    const credentials = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ client_id, client_secret });
    defer allocator.free(credentials);

    var buffer: [1024]u8 = undefined;
    @memset(&buffer, 0);

    const encoded_length = Encoder.calcSize(credentials.len);
    const encoded_creds = try allocator.alloc(u8, encoded_length);
    defer allocator.free(encoded_creds);

    _ = Encoder.encode(encoded_creds, credentials);

    const authorization_header_str = try std.fmt.allocPrint(allocator, "Basic {s}", .{encoded_creds});
    defer allocator.free(authorization_header_str);
    const authorization_header = std.http.Client.Request.Headers.Value{ .override = authorization_header_str };

    const url = try std.Uri.parse("https://accounts.spotify.com/api/token");
    const body = "grant_type=client_credentials";

    const buf = try allocator.alloc(u8, 1024 * 1024 * 4);
    defer allocator.free(buf);

    const headers = std.http.Client.Request.Headers{ .authorization = authorization_header, .content_type = std.http.Client.Request.Headers.Value{ .override = "application/x-www-form-urlencoded" } };
    var req = try client.open(std.http.Method.POST, url, std.http.Client.RequestOptions{ .headers = headers, .server_header_buffer = buf });
    req.transfer_encoding = .{ .content_length = body.len };

    try req.send();
    _ = try req.writeAll(body);
    try req.finish();
    try req.wait();

    const response = req.response;
    if (response.status.class() == std.http.Status.Class.success) {
        var rdr = req.reader();
        const token = try rdr.readAllAlloc(allocator, 1024 * 1024 * 4);
        std.debug.print("Token: {s}\n", .{token});
        return token;
    } else {
        std.debug.panic("Failed to fetch token\n", .{});
    }
}

test "spotify token" {
    const allocator = std.testing.allocator;
    const tok = try get_spotify_token(allocator);
    std.debug.warn("token: {s}", .{tok});
}
