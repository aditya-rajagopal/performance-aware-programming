const std = @import("std");
const sim8086 = @import("sim8086");

pub fn main() !void {
    const file = try std.fs.cwd().openFile("./src/listings/listing_0037_single_register_mov", .{});
    defer file.close();
    var buffer: [10240]u8 = undefined;
    const data = try file.reader().readAll(&buffer);
    const output = sim8086.disassemble(buffer[0..data]);
    std.debug.print("Disassembled:\n {any}\n", .{output});
}
