const std = @import("std");

pub fn assert(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (!condition) {
        std.log.err(fmt, args);
    }
}
