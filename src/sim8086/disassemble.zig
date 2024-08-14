const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils");
const Tables = @import("tables.zig");

pub fn disassemble(bytecode: []const u8, allocator: Allocator) ![]const u8 {
    var disassembly = try std.ArrayList(u8).initCapacity(allocator, bytecode.len * 5);
    // utils.print_bytecode(bytecode);

    try disassembly.appendSlice("bits 16\n\n");

    var inst_ptr: usize = 0;
    while (inst_ptr < bytecode.len) : (try disassembly.appendSlice("\n")) {
        const op = bytecode[inst_ptr];
        const op_code = find_op_code(op);
        inst_ptr += 1;

        const location = @as(usize, @intCast(@intFromEnum(op_code)));

        try disassembly.appendSlice(Tables.inst_to_string[location]);
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
    _ = disassembly.pop(); // remove the last \n
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
    const mode: Tables.Mode = @enumFromInt(mod);
    switch (mode) {
        .mem_reg_mode => {
            var strings: [2][]const u8 = undefined;
            const reg_indx: usize = (w << 3);

            strings[0] = Tables.Registers[reg_indx | reg];
            strings[1] = Tables.Registers[reg_indx | rm];

            try disassembly.appendSlice(strings[d ^ 1]);
            try disassembly.appendSlice(", ");
            try disassembly.appendSlice(strings[d]);
        },
        else => unreachable,
    }
}

fn find_op_code(op_bytecode: u8) Tables.instruction {
    inline for (std.meta.fields(Tables.instruction)) |f| {
        // std.debug.print("Field: {b:0>8}, op_code: {b:0>8}, res: {b:0>8}\n", .{ f.value, op_bytecode, f.value & op_bytecode });
        if (f.value & op_bytecode == f.value) {
            return @enumFromInt(f.value);
        }
    }
    unreachable;
}

const test_struct = struct {
    input: []const u8,
    output: []const u8,
};

test "find_op_code" {
    const test_cases = [_]struct {
        input: u8,
        output: Tables.instruction,
    }{
        .{ .input = 0b10001000, .output = .mov_reg_reg },
    };

    const debug: bool = true;

    for (test_cases, 0..) |case, i| {
        if (debug) {
            std.debug.print("Test[{d}]" ++ "--" ** 20 ++ "\n", .{i});
            std.debug.print("Input: 0b{b:0>8}\n", .{case.input});
        }
        const op_code = find_op_code(case.input);
        try testing.expectEqual(case.output, op_code);
        if (debug) {
            std.debug.print("Output: {s}", .{@tagName(op_code)});
        }
    }
}

test "mov" {
    const test_cases = [_]test_struct{
        .{ .input = &[_]u8{ 137, 217 }, .output = "bits 16\n\nmov cx, bx" },
        .{ .input = &[_]u8{ 136, 229 }, .output = "bits 16\n\nmov ch, ah" },
        .{ .input = &[_]u8{ 137, 222 }, .output = "bits 16\n\nmov si, bx" },
        .{ .input = &[_]u8{ 137, 251, 136, 200 }, .output = "bits 16\n\nmov bx, di\nmov al, cl" },
    };
    try test_inputs(&test_cases, false);
}

fn test_inputs(test_cases: []const test_struct, debug: bool) !void {
    for (test_cases, 0..) |case, i| {
        if (debug) {
            std.debug.print("Test[{d}]" ++ "--" ** 20 ++ "\n", .{i});
            std.debug.print("Input: {any}\n\n", .{case.input});
        }
        const output = try disassemble(case.input, std.testing.allocator);
        defer std.testing.allocator.free(output);
        if (debug) {
            std.debug.print("Output:\n{s}\n", .{output});
        }

        try testing.expectEqualSlices(u8, case.output, output);
    }
}
