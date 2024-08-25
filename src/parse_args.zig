const std = @import("std");

const options = [_][]const u8{
    "-d",
    "--disassemble",
    "-h",
    "--help",
    "-o",
    "--output",
    "-s",
    "--sim",
    "-v",
    "--verbose",
    "-md",
    "--mem_dump",
};

pub const Config = struct {
    disassemble: ?[]const u8 = null,
    simulate: ?[]const u8 = null,
    output: ?[]const u8 = null,
    enable_output: bool = false,
    help: bool = false,
    verbose: bool = false,
    mem_dump: bool = false,
    is_error: bool = false,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.disassemble) |d| {
            allocator.free(d);
        }
        if (self.simulate) |s| {
            allocator.free(s);
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
    \\      -v, --verbose <?path>       Enable printing of each instruction and change in register states
    \\      -md, --mem_dump <?path>     Dump memory to std out
    \\      -d, --disassemble <path>    file you want to disassemble
    \\      -s, --sim <path>            Takes a binary file and simulates an Intel 8086 running the provided bytecode
    \\                                  stream. Outputs the change in register states as the instructions are processed
    \\                                  and then the final register states.
    \\      -o, --output <?path>        location to store the disassembled result or the output of the simulator
    \\                                  or empty path to store it in the same location with a prefix sim8086
;

pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next().?;
    // std.debug.print("zig: {s}\n", .{zig});

    var config: Config = .{};
    config.disassemble = null;
    config.output = null;
    config.simulate = null;

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
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        }
        if (std.mem.eql(u8, arg, "-md") or std.mem.eql(u8, arg, "--mem_dump")) {
            config.mem_dump = true;
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
        if ((std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--sim")) and config.simulate == null) {
            temp_arg = args.next();
            if (temp_arg) |f| {
                for (options) |o| {
                    if (std.mem.eql(u8, o, f)) {
                        std.log.err("{s}", .{usage});
                        std.log.err("--sim/-s must have a path following it: found {s}", .{f});
                        config.is_error = true;
                        break :outter;
                    }
                }
                config.simulate = try allocator.dupe(u8, f);
            } else {
                std.log.err("{s}", .{usage});
                std.log.err("-s/--sim must have a path following it", .{});
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
