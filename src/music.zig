const std = @import("std");
const zap = @import("zap");
const zemplate = @import("zemplate");
const zdotenv = @import("zdotenv");
const print = std.debug.print;
const warn = std.log.warn;

pub const SortedAlbumList = struct {
    const AlbumList = std.DoublyLinkedList(MusicInfo.AlbumItem);
    const Self = @This();
    list: AlbumList,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .list = AlbumList{
                .first = null,
                .last = null,
                .len = 0,
            },
            .allocator = allocator,
        };
    }

    /// first node should be the earliest album in the list
    fn push(self: *Self, album: MusicInfo.AlbumItem) !void {
        const node = try self.allocator.create(AlbumList.Node);
        node.* = AlbumList.Node{ .data = album, .next = null, .prev = null };

        if (self.list.first == null) {
            self.list.prepend(node);
            return;
        }

        var current = self.list.first;
        while (current) |curr| {
            if (earlier_than(album, curr.data) orelse false) {
                self.list.insertBefore(curr, node);
                return;
            }

            if (curr.next == null) {
                self.list.append(node);
                return;
            }

            current = curr.next;
        }
    }

    /// sort function should return true if lhs is less than rhs
    /// release date is YYYY-MM-DD
    /// if returns Ok null, values are equal
    fn earlier_than(lhs: MusicInfo.AlbumItem, rhs: MusicInfo.AlbumItem) ?bool {
        var lhs_split = std.mem.splitScalar(u8, lhs.release_date, '-');
        var rhs_split = std.mem.splitScalar(u8, rhs.release_date, '-');
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
    albums_html: std.ArrayList(u8),

    const AlbumItem = struct {
        images: []struct {
            url: []u8,
            height: u32,
            width: u32,
        },
        name: []u8,
        release_date: []u8,
        external_urls: struct {
            spotify: []u8,
        },
    };

    const MusicComponentElementName = "music-display";

    pub fn build(allocator: std.mem.Allocator) !MusicInfo {
        var builder_gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const builder_allocator = builder_gpa.allocator();

        var client = Client{ .allocator = allocator };
        defer client.deinit();
        defer {
            while (client.connection_pool.used.popFirst()) |conn| {
                conn.data.close(allocator);
            }
        }

        var builder = try MusicInfoBuilder.init(&client, builder_allocator);

        const token = try builder.get_spotify_token();
        defer token.deinit();
        std.log.debug("got token\n", .{});

        var sorted_list = SortedAlbumList.init(allocator);
        const albums = try builder.get_albums_first(token.value);
        std.log.debug("got albums\n", .{});

        for (albums.value.items) |album| {
            try sorted_list.push(album);
        }

        if (albums.value.next) |uri| {
            try builder.get_albums_rest(uri, token.value, &sorted_list);
            std.log.debug("got rest: {d}\n", .{sorted_list.list.len});
        }

        const albums_html = try render_albums_html(allocator, &sorted_list);

        std.log.warn("should return music info", .{});
        return MusicInfo{ .albums_html = albums_html };
    }

    pub fn deinit(self: *@This()) void {
        self.albums_html.deinit();
    }

    fn render_albums_html(allocator: std.mem.Allocator, all_albums: *SortedAlbumList) !std.ArrayList(u8) {
        var buffer = std.ArrayList(u8).init(allocator);

        while (all_albums.list.pop()) |album_node| {
            defer all_albums.allocator.destroy(album_node);
            const album = album_node.data;
            const album_str = try std.fmt.allocPrint(allocator,
                \\
                \\<{s} name="{s}" image="{s}" release="{s}" spotify_url="{s}" >
                \\</{s}>
                \\
            , .{
                MusicComponentElementName,
                album.name,
                album.images[0].url,
                album.release_date,
                album.external_urls.spotify,
                MusicComponentElementName,
            });

            try buffer.appendSlice(album_str);
        }
        return buffer;
    }
};

pub const MusicTemplate = zemplate.template.Template(MusicInfo, @embedFile("pages/music.html"));
pub fn music_handler(ctx: *MusicTemplate, r: zap.Request) void {
    var body = ctx.render() catch |err| {
        std.debug.panic("Failed to render template: {any}", .{err});
    };
    print("body: {s}\n", .{body.items});
    defer body.deinit();

    r.sendBody(body.items) catch return;
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
        items: []MusicInfo.AlbumItem,
        next: ?[]u8,
    };

    /// A single entry in the `items` field
    fn init(client: *Client, allocator: std.mem.Allocator) !MusicInfoBuilder {
        return MusicInfoBuilder{
            .client = client,
            .allocator = allocator,
        };
    }

    /// As per spotify's client credential flow:
    /// https://developer.spotify.com/documentation/web-api/tutorials/client-credentials-flow
    fn get_spotify_token(self: *Self) !std.json.Parsed(SpotifyToken) {
        var env = try zdotenv.Zdotenv.init(self.allocator);
        try env.load();

        const env_map = try std.process.getEnvMap(self.allocator);

        const client_id = env_map.get("SPOTIFY_CLIENT_ID") orelse return error.NoClientId;
        const client_secret = env_map.get("SPOTIFY_CLIENT_SECRET") orelse return error.NoClientSecret;
        const credentials = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ client_id, client_secret });
        defer self.allocator.free(credentials);

        var buffer: [1024]u8 = undefined;
        @memset(&buffer, 0);

        const encoded_length = Encoder.calcSize(credentials.len);
        const encoded_creds = try self.allocator.alloc(u8, encoded_length);
        defer self.allocator.free(encoded_creds);

        _ = Encoder.encode(encoded_creds, credentials);

        const authorization_header_str = try std.fmt.allocPrint(self.allocator, "Basic {s}", .{encoded_creds});
        defer self.allocator.free(authorization_header_str);
        const authorization_header = std.http.Client.Request.Headers.Value{ .override = authorization_header_str };

        const uri = try std.Uri.parse("https://accounts.spotify.com/api/token");
        const payload = "grant_type=client_credentials";

        const buf = try self.allocator.alloc(u8, 1024 * 1024 * 4);
        defer self.allocator.free(buf);
        var response_body = std.ArrayList(u8).init(self.allocator);
        defer response_body.deinit();

        const headers = std.http.Client.Request.Headers{ .authorization = authorization_header, .content_type = std.http.Client.Request.Headers.Value{ .override = "application/x-www-form-urlencoded" } };
        const req_options = std.http.Client.FetchOptions{
            .payload = payload,
            .server_header_buffer = buf,
            .method = std.http.Method.POST,
            .headers = headers,
            .location = std.http.Client.FetchOptions.Location{ .uri = uri },
            .response_storage = .{ .dynamic = &response_body },
        };
        std.log.debug("options\n", .{});
        var res = try self.client.fetch(req_options);
        std.log.debug("sent\n", .{});

        if (res.status.class() == std.http.Status.Class.success) {
            std.log.debug("token response json string: {s}\n", .{response_body.items});
            const token = try std.json.parseFromSlice(
                SpotifyToken,
                self.allocator,
                response_body.items,
                .{},
            );

            std.log.debug("parsed json\n", .{});
            return token;
        } else {
            std.debug.panic("Failed to fetch token\nStatus: {any}\n", .{res.status});
        }
    }

    /// First request to get albums, object returns with a `next` field that may need to be called to get more
    fn get_albums_first(self: *Self, token: SpotifyToken) !std.json.Parsed(GetAlbumsRes) {
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
        const headers = std.http.Client.Request.Headers{ .authorization = authorization_header, .content_type = std.http.Client.Request.Headers.Value{ .override = "application/json" } };

        var response_body = std.ArrayList(u8).init(self.allocator);
        defer response_body.deinit();
        const req_options = std.http.Client.FetchOptions{
            .server_header_buffer = buf,
            .method = std.http.Method.GET,
            .headers = headers,
            .location = std.http.Client.FetchOptions.Location{ .uri = uri },
            .response_storage = .{ .dynamic = &response_body },
        };

        var res = try self.client.fetch(req_options);

        if (res.status.class() == std.http.Status.Class.success) {
            const parsed = try std.json.parseFromSlice(
                GetAlbumsRes,
                self.allocator,
                response_body.items,
                .{
                    .ignore_unknown_fields = true,
                },
            );

            return parsed;
        } else {
            std.debug.panic("Failed to fetch albums: {any}\n", .{res.status});
        }
    }

    fn get_albums_rest(self: *Self, init_page_url: []u8, token: SpotifyToken, list: *SortedAlbumList) !void {
        var next_page: ?[]u8 = init_page_url;

        while (next_page) |page_uri| {
            const uri = try std.Uri.parse(page_uri);

            const buf = try self.allocator.alloc(u8, 1024 * 1024 * 4);
            defer self.allocator.free(buf);

            const authorization_header_str = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token.access_token});
            defer self.allocator.free(authorization_header_str);

            const authorization_header = std.http.Client.Request.Headers.Value{ .override = authorization_header_str };
            const headers = std.http.Client.Request.Headers{ .authorization = authorization_header, .content_type = std.http.Client.Request.Headers.Value{ .override = "application/json" } };

            var response_body = std.ArrayList(u8).init(self.allocator);
            defer response_body.deinit();
            const req_options = std.http.Client.FetchOptions{
                .server_header_buffer = buf,
                .method = std.http.Method.GET,
                .headers = headers,
                .location = std.http.Client.FetchOptions.Location{ .uri = uri },
                .response_storage = .{ .dynamic = &response_body },
            };

            var res = try self.client.fetch(req_options);

            if (res.status.class() == std.http.Status.Class.success) {
                const parsed = try std.json.parseFromSlice(
                    GetAlbumsRes,
                    self.allocator,
                    response_body.items,
                    .{
                        .ignore_unknown_fields = true,
                    },
                );
                next_page = parsed.value.next;
                for (parsed.value.items) |album| {
                    try list.push(album);
                }
            } else {
                std.debug.panic("Failed to fetch albums: {any}\n", .{res.status});
            }
        }
    }
};
