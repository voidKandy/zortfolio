const std = @import("std");
const zemplate = @import("zemplate");
const zyph = @import("zyph");
const dotenv = @import("dotenv");
const print = std.debug.print;
const log = std.log.scoped(.music);
const Request = std.http.Server.Request;

const AlbumItemResponse = struct {
    images: []Image,
    name: []u8,
    release_date: []u8,
    external_urls: struct {
        spotify: []u8,
    },

    const Image = struct {
        url: []u8,
        height: u32,
        width: u32,
    };
};

const AlbumItem = struct {
    item: AlbumItemResponse,
    node: std.DoublyLinkedList.Node,
};

const TemplateAlbumItem = struct {
    name: []u8,
    release_date: []u8,
    image_url: []u8,
    spotify_url: []u8,
};

pub const SortedAlbumList = struct {
    const Self = @This();
    list: std.DoublyLinkedList = .{},

    fn toArray(self: *Self, a: std.mem.Allocator) std.mem.Allocator.Error![]TemplateAlbumItem {
        const size = self.list.len();

        var arr = try a.alloc(TemplateAlbumItem, size);
        var i: usize = 0;
        while (self.list.pop()) |n| : (i += 1) {
            const item: *AlbumItem = @fieldParentPtr("node", n);
            arr[i] = TemplateAlbumItem{
                .image_url = item.item.images[0].url,
                .name = item.item.name,
                .release_date = item.item.release_date,
                .spotify_url = item.item.external_urls.spotify,
            };
        }

        return arr;
    }

    /// first node should be the earliest album in the list
    /// converts AlbumResponse object into AlbumItem object
    fn pushAlbumResponse(self: *Self, allocator: std.mem.Allocator, album_res: *const AlbumItemResponse) !void {
        const response_copy =
            AlbumItemResponse{
                .images = try allocator.dupe(AlbumItemResponse.Image, album_res.*.images),
                .name = try allocator.dupe(u8, album_res.*.name),
                .release_date = try allocator.dupe(u8, album_res.*.release_date),
                .external_urls = .{ .spotify = try allocator.dupe(u8, album_res.*.external_urls.spotify) },
            };

        const node = try allocator.create(std.DoublyLinkedList.Node);
        const album = try allocator.create(AlbumItem);
        album.* = AlbumItem{ .item = response_copy, .node = node.* };

        if (self.list.first == null) {
            self.list.prepend(&album.node);
            return;
        }

        var current = self.list.first;
        while (current) |curr| {
            const current_album = @as(*AlbumItem, @fieldParentPtr("node", curr));
            if (earlierThan(
                current_album.*,
                album.*,
            ) orelse true) {
                self.list.insertBefore(curr, &album.node);
                return;
            }

            if (curr.next == null) {
                self.list.append(&album.node);
                return;
            }

            current = (current orelse break).next;
        }
    }

    /// sort function should return true if lhs is less than rhs
    /// release date is YYYY-MM-DD
    /// if returns Ok null, values are equal
    fn earlierThan(lhs: AlbumItem, rhs: AlbumItem) ?bool {
        var lhs_split = std.mem.splitScalar(u8, lhs.item.release_date, '-');
        var rhs_split = std.mem.splitScalar(u8, rhs.item.release_date, '-');
        while (lhs_split.next()) |lhs_str| {
            const rhs_str = rhs_split.next() orelse std.debug.panic("lhs and rhs are not formatted the same\nlhs: {any}\nrhs: {any}\n", .{ lhs, rhs });
            const rhs_num = std.fmt.parseInt(u32, rhs_str, 10) catch continue;
            const lhs_num = std.fmt.parseInt(u32, lhs_str, 10) catch continue;
            if (lhs_num != rhs_num) {
                const ret = lhs_num < rhs_num;
                return ret;
            }
        }
        return null;
    }
};

pub const MusicInfo = struct {
    all_albums: []TemplateAlbumItem,

    pub fn build(allocator: std.mem.Allocator) !MusicInfo {
        var builder = try MusicInfoBuilder.init(allocator);
        defer builder.deinit();

        var all_albums_sorted = SortedAlbumList{};

        const token = try builder.getSpotifyToken();
        defer token.deinit();
        log.debug("got token\n", .{});

        const albums = try builder.getAlbumsFirst(token.value);
        defer albums.deinit();
        log.debug("got albums\n", .{});

        for (0..albums.value.items.len) |i| {
            const album = albums.value.items[i];
            try all_albums_sorted.pushAlbumResponse(allocator, &album);
        }

        if (albums.value.next) |uri| {
            try builder.getAlbumsRest(uri, token.value, &all_albums_sorted);
        }

        // const albums_html = try renderAlbumsHTML(allocator, &all_albums_sorted);
        const all_albums = try all_albums_sorted.toArray(allocator);

        log.debug("should return music info", .{});
        return MusicInfo{ .all_albums = all_albums };
    }

    pub fn deinit(self: *@This(), a: std.mem.Allocator) void {
        a.free(self.all_albums);
    }
};

pub fn musicHandler(ctx: *MusicInfo, a: std.mem.Allocator, _: Request, w: *std.Io.Writer) anyerror!void {
    var t = try zemplate.Template(MusicInfo).init(a, ctx.*);
    defer t.deinit();
    const render = try t.render(@embedFile("music.html"), .{});
    try w.writeAll(render);
}

const Encoder = std.base64.standard.Encoder;
const Decoder = std.base64.standard.Decoder;
const Client = std.http.Client;

const MusicInfoBuilder = struct {
    const Self = @This();
    client: *Client,
    allocator: std.mem.Allocator,

    /// Returned by initial request to get token needed to use the Spotify Api
    const SpotifyToken = struct {
        access_token: []u8,
        token_type: []u8,
        expires_in: u32,
    };

    /// https://developer.spotify.com/documentation/web-api/reference/get-an-artists-albums
    /// Object returned by get artist albums
    const GetAlbumsRes = struct {
        items: []AlbumItemResponse,
        next: ?[]u8,
    };

    fn init(allocator: std.mem.Allocator) !MusicInfoBuilder {
        const client = try allocator.create(Client);
        client.* = .{
            .allocator = allocator,
        };
        return MusicInfoBuilder{
            .client = client,
            .allocator = allocator,
        };
    }

    fn deinit(self: Self) void {
        self.client.deinit();
    }

    /// As per spotify's client credential flow:
    /// https://developer.spotify.com/documentation/web-api/tutorials/client-credentials-flow
    fn getSpotifyToken(self: *Self) !std.json.Parsed(SpotifyToken) {
        var env_map = try std.process.getEnvMap(self.allocator);
        defer env_map.deinit();

        const client_id = env_map.get("SPOTIFY_CLIENT_ID") orelse return error.NoClientId;
        const client_secret = env_map.get("SPOTIFY_CLIENT_SECRET") orelse return error.NoClientSecret;
        const credentials = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ client_id, client_secret });
        defer self.allocator.free(credentials);

        // var buffer: [1024]u8 = undefined;
        // @memset(&buffer, 0);

        const encoded_length = Encoder.calcSize(credentials.len);
        const encoded_creds = try self.allocator.alloc(u8, encoded_length);
        defer self.allocator.free(encoded_creds);

        _ = Encoder.encode(encoded_creds, credentials);

        const authorization_header_str = try std.fmt.allocPrint(self.allocator, "Basic {s}", .{encoded_creds});
        defer self.allocator.free(authorization_header_str);
        const authorization_header = std.http.Client.Request.Headers.Value{ .override = authorization_header_str };

        const uri = try std.Uri.parse("https://accounts.spotify.com/api/token");
        const payload = "grant_type=client_credentials";

        const headers = std.http.Client.Request.Headers{
            .authorization = authorization_header,
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
            .accept_encoding = .{ .override = "identity" },
        };

        var req = try self.client.request(.POST, uri, .{
            .headers = headers,
        });
        defer req.deinit();

        try req.sendBodyComplete(@constCast(payload));
        var res = try req.receiveHead(&.{});

        const response_transfer_buffer = try self.allocator.alloc(u8, 1024 * 1024);
        defer self.allocator.free(response_transfer_buffer);

        const body_reader = res.reader(response_transfer_buffer);
        const res_body = try body_reader.allocRemaining(self.allocator, .unlimited);

        if (res.head.status.class() == std.http.Status.Class.success) {
            log.debug("token response json string: {s}\n", .{res_body});
            const token = try std.json.parseFromSlice(
                SpotifyToken,
                self.allocator,
                res_body,
                .{},
            );

            return token;
        } else {
            std.debug.panic("Failed to fetch token\nStatus: {any}\n", .{res.head.status});
        }
    }

    /// First request to get albums, object returns with a `next` field that may need to be called to get more
    fn getAlbumsFirst(self: *Self, token: SpotifyToken) !std.json.Parsed(GetAlbumsRes) {
        // Void Kandy's ID
        const artist_id = "19BbMfHJwXYA8zKWAs8cel";
        const uri_str = try std.fmt.allocPrint(self.allocator, "https://api.spotify.com/v1/artists/{s}/albums?include_groups=album,single", .{artist_id});
        defer self.allocator.free(uri_str);

        const uri = try std.Uri.parse(uri_str);

        const buf = try self.allocator.alloc(u8, 1024 * 1024 * 4);
        defer self.allocator.free(buf);

        const authorization_header_str = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token.access_token});
        defer self.allocator.free(authorization_header_str);

        const authorization_header = std.http.Client.Request.Headers.Value{ .override = authorization_header_str };
        const headers = std.http.Client.Request.Headers{
            .authorization = authorization_header,
            .content_type = .{ .override = "application/json" },
            .accept_encoding = .{ .override = "identity" },
        };

        var req = try self.client.request(.GET, uri, .{
            .headers = headers,
        });
        defer req.deinit();

        try req.sendBodiless();
        var res = try req.receiveHead(&[_]u8{});

        const response_transfer_buffer = try self.allocator.alloc(u8, 1024 * 1024);
        defer self.allocator.free(response_transfer_buffer);

        const body_reader = res.reader(response_transfer_buffer);
        const res_body = try body_reader.allocRemaining(self.allocator, .unlimited);

        if (res.head.status.class() == std.http.Status.Class.success) {
            const parsed = try std.json.parseFromSlice(
                GetAlbumsRes,
                self.allocator,
                res_body,
                .{
                    .ignore_unknown_fields = true,
                },
            );

            return parsed;
        } else {
            std.debug.panic("Failed to fetch albums: {any}\n", .{res.head.status});
        }
    }

    fn getAlbumsRest(self: *Self, init_page_url: []u8, token: SpotifyToken, list: *SortedAlbumList) !void {
        var next_page: ?[]u8 = init_page_url;

        while (next_page) |page_uri| {
            const uri = try std.Uri.parse(page_uri);

            const buf = try self.allocator.alloc(u8, 1024 * 1024 * 4);
            defer self.allocator.free(buf);

            const authorization_header_str = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token.access_token});
            defer self.allocator.free(authorization_header_str);

            const authorization_header = std.http.Client.Request.Headers.Value{ .override = authorization_header_str };

            const headers = std.http.Client.Request.Headers{
                .authorization = authorization_header,
                .content_type = .{ .override = "application/json" },
                .accept_encoding = .{ .override = "identity" },
            };
            var req = try self.client.request(.GET, uri, .{
                .headers = headers,
            });
            defer req.deinit();

            try req.sendBodiless();
            var res = try req.receiveHead(&[_]u8{});

            const response_transfer_buffer = try self.allocator.alloc(u8, 1024 * 1024);
            defer self.allocator.free(response_transfer_buffer);

            const body_reader = res.reader(response_transfer_buffer);
            const res_body = try body_reader.allocRemaining(self.allocator, .unlimited);

            if (res.head.status.class() == std.http.Status.Class.success) {
                const parsed = try std.json.parseFromSlice(
                    GetAlbumsRes,
                    self.allocator,
                    res_body,
                    .{
                        .ignore_unknown_fields = true,
                    },
                );
                next_page = parsed.value.next;

                for (0..parsed.value.items.len) |i| {
                    const album = parsed.value.items[i];
                    try list.pushAlbumResponse(self.allocator, &album);
                }
            } else {
                std.debug.panic("Failed to fetch albums: {any}\n", .{res.head.status});
            }
        }
    }
};
