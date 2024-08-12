const std = @import("std");
const testing = std.testing;

pub fn disassemble(bytecode: []const u8) []const u8 {
    std.debug.print("bytecode recieved: {any}\n", .{bytecode});
    return bytecode;
}

test "basic add functionality" {}
