const std = @import("std");
const Config = @import("config/config.zig").Config;
const Server = @import("server.zig").Server;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var conf = Config.init("config/main_config.json", arena.allocator()) catch |err| {
        std.log.err("Failed to load configuration file 'config/main_config.json': {any}", .{err});
        return;
    };
    defer conf.deinitBuilder();

    var server = Server.init(&conf, allocator);
    try server.run();
}
