const std = @import("std");
const core = @import("core");
const configuration = @import("config");
const SharedConfig = @import("common").SharedConfig;

const cli = @import("cup_cli/cup_cli.zig");

const Strategy = @import("loadBalancer").Strategy;

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

const ops = core.server_ops;
const Epoll = core.Epoll;
const Connection = core.conn.Connection;
const ConnectionData = core.conn.ConnectionData;
const ConfigManager = configuration.ConfigManager;
const Config = configuration.Config;

// strat the server with epoll
pub fn start(server_address: std.net.Address, config_manager: ConfigManager, shared_config: SharedConfig) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var server_addy = server_address;

    var tcp_server = server_addy.listen(.{
        .reuse_address = true,
        .reuse_port = true,
    }) catch |err| {
        std.log.err("Failed to start listening on server: {any}\n", .{err});
        return;
    };
    defer tcp_server.deinit();

    const epoll = try Epoll.init(tcp_server.stream.handle);
    defer epoll.deinit();

    var connection = Connection.init(allocator);
    defer connection.deinit();

    var thread_pool: Pool = undefined;

    try thread_pool.init(Pool.Options{
        .allocator = allocator,
    });
    defer thread_pool.deinit();

    var wait_group: WaitGroup = undefined;
    wait_group.reset();

    var cm = config_manager;

    // Spawn configuration watcher
    thread_pool.spawnWg(&wait_group, configChangeWatcher, .{
        allocator,
        &cm,
        shared_config,
    });

    try mainEventLoop(&tcp_server, epoll, &wait_group, &thread_pool, &cm, &connection);

    // Work on threads after scheduling all tasks
    thread_pool.waitAndWork(&wait_group);
}

fn mainEventLoop(
    tcp_server: *std.net.Server,
    epoll: Epoll,
    wait_group: *WaitGroup,
    thread_pool: *Pool,
    config_manager: *ConfigManager,
    connection: *Connection,
) !void {
    var events: [1024]std.os.linux.epoll_event = undefined;

    while (true) {
        const nfds = epoll.wait(&events);
        var config = config_manager.getCurrentConfig();
        for (events[0..nfds]) |event| {
            if (event.data.fd == tcp_server.stream.handle) {
                try ops.acceptIncomingConnections(tcp_server, epoll, config.conf.ssl, connection);
            } else {
                const conn: ?*ConnectionData = @ptrFromInt(event.data.ptr);
                thread_pool.spawnWg(wait_group, handleRequest, .{
                    epoll.epoll_fd,
                    &config,
                    conn.?,
                    connection,
                });
            }
        }
    }
}

fn configChangeWatcher(
    allocator: std.mem.Allocator,
    config_manager: *ConfigManager,
    sh_config: SharedConfig,
) void {
    var current_config: usize = 1;
    var config: Config = undefined;
    defer config.deinit();

    while (true) {
        const file_data = sh_config.readData();

        var parts = std.mem.split(u8, file_data[0..], "|");
        const new_config = parseConfigVersion(parts.next().?) catch {
            return;
        };

        if (current_config != new_config) {
            const parsed_config = parseConfigJSON(parts.next().?);
            config = Config.init(parsed_config, allocator, null, new_config, false) catch |err| {
                std.log.err("Config parse error: {any}", .{err});
                return;
            };

            config_manager.pushNewConfig(config) catch |e| {
                std.log.err("push err:{any}", .{e});
                return;
            };
            current_config = new_config;
        }
        std.time.sleep(100_000);
    }
}

fn parseConfigVersion(data: []const u8) !usize {
    return std.fmt.parseInt(usize, data, 10) catch |err| {
        std.log.err("parse err: {any}", .{err});
        return err;
    };
}

fn parseConfigJSON(json_data: []const u8) []u8 {
    const json = std.mem.trimRight(u8, json_data, &[_]u8{ 0, '\n', '\r', ' ', '\t' });
    var buffer: [4096]u8 = undefined;

    std.mem.copyForwards(u8, &buffer, json);

    return buffer[0..json.len];
}

fn handleRequest(
    epoll_fd: std.posix.fd_t,
    config: *Config,
    conn: *ConnectionData,
    connection: *Connection,
) void {
    var request_buffer: [4094]u8 = undefined;
    var response_buffer: [4094]u8 = undefined;

    const request = ops.readClientRequest(conn.*, &request_buffer) catch {
        ops.sendBadRequest(conn.*) catch {};
        return;
    };

    const path_info = extractPath(request) catch {
        handleError(conn, epoll_fd, connection);
        return;
    };

    const selected_strategy = config.conf.strategy_hash.get(path_info.path);

    if (selected_strategy) |ss| {
        ss.handle(conn.*, request, &response_buffer) catch {};
        ops.closeConnection(epoll_fd, conn, connection) catch {};
        return;
    }

    if (path_info.sub) {
        var paths = std.mem.split(u8, path_info.path[1..], "/");
        var buf_route: [1024]u8 = undefined;
        while (paths.next()) |path| {
            const route = std.fmt.bufPrint(&buf_route, "/{s}/*", .{path}) catch {
                return;
            };
            var strategy = config.conf.strategy_hash.get(route) orelse continue;
            strategy.handle(conn.*, request, &response_buffer) catch {};
            ops.closeConnection(epoll_fd, conn, connection) catch {};
            return;
        }
    }
    var general_strategy = config.conf.strategy_hash.get("*") orelse unreachable;

    general_strategy.handle(conn.*, request, &response_buffer) catch {};
    ops.closeConnection(epoll_fd, conn, connection) catch {};
}

fn handleError(conn: *ConnectionData, epoll_fd: std.posix.fd_t, connection: *Connection) void {
    ops.sendBadGateway(conn.*) catch {};
    ops.closeConnection(epoll_fd, conn, connection) catch {};
}

const ExtractedPath = struct {
    sub: bool,
    path: []const u8,
};

pub fn extractPath(request: []const u8) !ExtractedPath {
    const first_space_index = std.mem.indexOf(u8, request, " ") orelse return error.InvalidPath;
    const second_space_index = std.mem.indexOf(u8, request[first_space_index + 1 ..], " ") orelse return error.InvalidPath;

    var path = request[first_space_index + 1 .. first_space_index + 1 + second_space_index];

    if (std.mem.indexOf(u8, path, "?")) |query_index| {
        path = path[0..query_index];
    }

    if (path.len > 1 and std.mem.endsWith(u8, path, "/")) {
        path = path[0 .. path.len - 1];
    }

    const sub_route = std.mem.indexOf(u8, path[1..], "/") != null and path.len > 1;

    return ExtractedPath{
        .sub = sub_route,
        .path = path,
    };
}

test "extractPath valid inputs" {
    try std.testing.expectEqualDeep(
        ExtractedPath{ .sub = false, .path = "/" },
        try extractPath("GET / HTTP/1.1"),
    );

    try std.testing.expectEqualDeep(
        ExtractedPath{ .sub = false, .path = "/path" },
        try extractPath("GET /path HTTP/1.1"),
    );

    try std.testing.expectEqualDeep(
        ExtractedPath{ .sub = false, .path = "/path" },
        try extractPath("GET /path?key=value HTTP/1.1"),
    );

    try std.testing.expectEqualDeep(
        ExtractedPath{ .sub = true, .path = "/parent/child" },
        try extractPath("GET /parent/child HTTP/1.1"),
    );

    try std.testing.expectEqualDeep(
        ExtractedPath{ .sub = false, .path = "/path" },
        try extractPath("GET /path/ HTTP/1.1"),
    );
}

test "extractPath invalid inputs" {
    try std.testing.expectError(error.InvalidPath, extractPath(""));
    try std.testing.expectError(error.InvalidPath, extractPath("GET HTTP/1.1"));
    try std.testing.expectError(error.InvalidPath, extractPath("INVALID REQUEST"));
}

test "parseConfigVersion parses valid version numbers" {
    const version = parseConfigVersion("42") catch unreachable;
    try std.testing.expect(version == 42);
}

test "parseConfigJSON trims and copies JSON data" {
    const json_data = "{ \"key\": \"value\" }\n";
    const result = parseConfigJSON(json_data);
    try std.testing.expectEqualStrings("{ \"key\": \"value\" }", result);
}

test "parseConfigJSON handles empty data" {
    const result = parseConfigJSON("");
    try std.testing.expectEqualStrings("", result);
}
