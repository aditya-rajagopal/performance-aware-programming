const std = @import("std");

pub fn print_bytecode(bytecode: []const u8) void {
    std.debug.print("Bytecode: \n", .{});
    std.debug.print("\t", .{});
    var count: usize = 0;
    for (bytecode) |byte| {
        std.debug.print("{b:0>8} ", .{byte});
        count += 1;
        if (@mod(count, 5) == 0) {
            std.debug.print("\n\t", .{});
        }
    }

    if (@mod(count, 5) != 0) {
        std.debug.print("\n", .{});
    }
}
