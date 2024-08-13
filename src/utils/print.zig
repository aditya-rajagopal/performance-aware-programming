const std = @import("std");

pub fn print_bytecode(bytecode: []const u8) void {
    std.debug.print("Bytecode {d}\n", .{bytecode});
}
