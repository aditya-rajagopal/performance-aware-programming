const std = @import("std");
const sim8086 = @import("sim8086");

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();
    //

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    const file = try std.fs.cwd().openFile("./src/listings/listing_0038_many_register_mov", .{});
    defer file.close();
    var buffer: [10240]u8 = undefined;
    const data = try file.reader().readAll(&buffer);
    const output = try sim8086.disassemble(buffer[0..data], allocator);
    defer allocator.free(output);
    std.debug.print("Disassembled:\n{s}\n", .{output});
}
