const std = @import("std");
const Config = @import("config/config.zig").Config;
const Server = @import("server.zig").Server;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed_config = Config.readConfigFile("config/main_config.json", allocator) catch |err| {
        std.log.err("Failed to load configuration file 'config/main_config.json': {any}", .{err});
        return;
    };

    var conf = Config.init(parsed_config, allocator);
    defer conf.deinit();

    const err = try conf.applyConfig();
    if (err != null) {
        std.log.err("{s}\n", .{err.?.err_message});
        return;
    }

    try Server.run(conf);
}
