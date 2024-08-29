const std = @import("std");

pub fn assert(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (!condition) {
        std.debug.panic(fmt, args);
    }
}

pub fn comptime_assert(comptime condition: bool, comptime fmt: []const u8, comptime args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const output = try std.fmt.bufPrint(&buffer, fmt, args);
    if (!condition) {
        @compileError(output);
    }
}
