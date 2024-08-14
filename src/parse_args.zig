const std = @import("std");

const options = [_][]const u8{
    "-d",
    "--disassemble",
    "-h",
    "--help",
    "-o",
    "--output",
};

pub const Config = struct {
    disassemble: ?[]const u8 = null,
    output: ?[]const u8 = null,
    enable_output: bool = false,
    help: bool = false,
    is_error: bool = false,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.disassemble) |d| {
            allocator.free(d);
        }
        if (self.output) |o| {
            allocator.free(o);
        }
    }
};

pub const usage =
    \\ 
    \\ Usage:
    \\ sim8086 [options]
    \\
    \\      -h, --help                  print usage
    \\      -d, --disassemble <path>    file you want to disassemble
    \\      -o, --output <?path>        location to store the disassembled result
    \\                                  or empty path to store it in the same location with a prefix sim8086
;

pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next().?;
    // std.debug.print("zig: {s}\n", .{zig});

    var config: Config = undefined;
    config.disassemble = null;
    config.output = null;

    var temp_arg = args.next();
    var arg: []const u8 = undefined;

    if (temp_arg) |a| {
        arg = a;
    } else {
        std.log.err("{s}", .{usage});
        std.log.err("Invalid argument: {s}", .{arg});
        config.is_error = true;
        return config;
    }

    outter: while (true) {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            config.help = true;
            break;
        }
        if ((std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--disassemble")) and config.disassemble == null) {
            temp_arg = args.next();
            if (temp_arg) |f| {
                for (options) |o| {
                    if (std.mem.eql(u8, o, f)) {
                        std.log.err("{s}", .{usage});
                        std.log.err("-b must have a path following it: found {s}", .{f});
                        config.is_error = true;
                        break :outter;
                    }
                }
                config.disassemble = try allocator.dupe(u8, f);
            } else {
                std.log.err("{s}", .{usage});
                std.log.err("-b must have a path following it", .{});
                config.is_error = true;
                break;
            }
        }
        if ((std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) and config.output == null) {
            temp_arg = args.next();
            config.enable_output = true;
            if (temp_arg) |f| {
                for (options) |o| {
                    if (std.mem.eql(u8, o, f)) {
                        arg = f;
                        continue :outter;
                    }
                }
                config.output = try allocator.dupe(u8, f);
            } else {
                break;
            }
        }
        temp_arg = args.next();
        if (temp_arg) |a| {
            arg = a;
        } else {
            break;
        }
    }

    return config;
}
