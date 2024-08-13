const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("utils");
const testing = std.testing;
const tables = @import("tables.zig");

pub fn disassemble(bytecode: []const u8, allocator: Allocator) ![]const u8 {
    var disassembly = try std.ArrayList(u8).initCapacity(allocator, bytecode.len * 5);
    utils.print_bytecode(bytecode);

    try disassembly.appendSlice("bits 16\n\n");
    var inst_ptr: usize = 0;
    while (inst_ptr < bytecode.len) {
        const op = bytecode[inst_ptr];
        const op_code = find_op_code(op);
        inst_ptr += 1;
        const location = @as(usize, @intCast(@intFromEnum(op_code)));
        try disassembly.appendSlice(tables.inst_to_string[location]);
        try disassembly.append(' ');
        // std.debug.print("op_code: {s}\n", .{@tagName(op_code)});
        switch (op_code) {
            .mov_reg_reg => {
                const payload = bytecode[inst_ptr];
                try disassemble_mov_reg_reg(op, payload, &disassembly);

                inst_ptr += 1;
            },
            else => unreachable,
        }
    }
    return disassembly.toOwnedSlice();
}

fn disassemble_mov_reg_reg(op: u8, payload: u8, disassembly: *std.ArrayList(u8)) !void {
    const d = (op >> 1) & 1;
    const w = op & 1;
    const mod = (payload >> 6) & 0b11;
    const reg = (payload >> 3) & 0b111;
    const rm = payload & 0b111;
    // std.debug.print(
    //     "mov: d:{b}, w:{b}, mod:{b:0>2}, reg:{b:0>3}, rm:{b:0>3} \n",
    //     .{ d, w, mod, reg, rm },
    // );
    const mode: tables.Mode = @enumFromInt(mod);
    switch (mode) {
        .mem_reg_mode => {
            var strings: [2][]const u8 = undefined;
            const reg_indx: usize = (w << 3);

            strings[0] = tables.Registers[reg_indx | reg];
            strings[1] = tables.Registers[reg_indx | rm];

            try disassembly.appendSlice(strings[d ^ 1]);
            try disassembly.appendSlice(", ");
            try disassembly.appendSlice(strings[d]);
            try disassembly.appendSlice("\n");
        },
        else => unreachable,
    }
}

fn find_op_code(op_bytecode: u8) tables.instruction {
    inline for (std.meta.fields(tables.instruction)) |f| {
        // std.debug.print("Field: {b:0>8}, op_code: {b:0>8}, res: {b:0>8}\n", .{ f.value, op_bytecode, f.value & op_bytecode });
        if (f.value & op_bytecode == f.value) {
            return @enumFromInt(f.value);
        }
    }
    unreachable;
}
