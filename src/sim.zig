const std = @import("std");
const sim8086 = @import("sim8086");
const parse_args = @import("parse_args.zig").parseArgs;
const usage_str = @import("parse_args.zig").usage;
const utils = @import("utils");

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var config = try parse_args(allocator);
    defer config.deinit(allocator);

    const outw = std.io.getStdOut().writer();
    if (config.help) {
        try outw.print("{s}", .{usage_str});
        return;
    }

    if (config.is_error) {
        return;
    }

    var output: []const u8 = undefined;
    defer allocator.free(output);

    // std.debug.print("config: {any}\n", .{config});

    if (config.disassemble) |d_file| {
        const file = try std.fs.cwd().openFile(d_file, .{});
        defer file.close();
        var buffer: [10240]u8 = undefined;
        const data = try file.reader().readAll(&buffer);
        if (config.verbose) {
            utils.print_bytecode(buffer[0..data]);
        }
        output = try sim8086.disassemble(buffer[0..data], allocator);
        if (config.verbose) {
            try outw.print("{s}\n", .{output});
        }
    } else if (config.simulate) |s_file| {
        var start = try std.time.Timer.start();
        const file = try std.fs.cwd().openFile(s_file, .{});
        defer file.close();
        var buffer: [10240]u8 = undefined;
        const data = try file.reader().readAll(&buffer);
        // utils.print_bytecode(buffer[0..data]);
        const file_read = start.lap();
        output = try sim8086.simulate(
            buffer[0..data],
            allocator,
            .{ .verbose = config.verbose, .mem_dump = config.mem_dump },
        );
        const simulation_time = start.read();
        std.debug.print("Time to run simulation: {s}, file_read: {s}\n", .{
            std.fmt.fmtDuration(simulation_time),
            std.fmt.fmtDuration(file_read),
        });
        try outw.print("{s}\n", .{output});
    } else {
        std.log.err("{s}", .{usage_str});
        std.log.err("Invalid usage: -d, --disassembly [path] must be provided", .{});
    }

    if (config.enable_output) {
        var out_file: []const u8 = undefined;
        defer allocator.free(out_file);

        if (config.output) |o| {
            out_file = try allocator.dupe(u8, o);
        } else {
            var file_name = config.disassemble.?;
            const seperators = [_]u8{ '\\', '/' };

            inline for (seperators) |sep| {
                const file_name_start = std.mem.lastIndexOfScalar(u8, file_name, sep);
                if (file_name_start) |f| {
                    file_name = file_name[f + 1 ..];
                }
            }
            out_file = try std.fmt.allocPrint(allocator, "./{s}{s}", .{ "sim8086_", file_name });
        }

        const file = try std.fs.cwd().createFile(out_file, .{});
        defer file.close();
        try file.writer().writeAll(output);
        try outw.print("Output written to: {s}", .{out_file});
    }
}
