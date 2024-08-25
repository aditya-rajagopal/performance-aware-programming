const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils");
const assert = utils.assert;
const Tables = @import("tables.zig");
const op_to_str_map = Tables.op_to_str_map;
const Operand = Tables.Operand;
const REP_FLAG = Tables.REP_FLAG;
const Z_FLAG = Tables.Z_FLAG;
const W_FLAG = Tables.W_FLAG;
const REL_JUMP_FLAG = Tables.REL_JUMP_FLAG;
const LOCK_FLAG = Tables.LOCK_FLAG;
const SEGMENT_OVERRIDE_FLAG = Tables.SEGMENT_OVERRIDE_FLAG;
const FAR_FLAG = Tables.FAR_FLAG;
const Instruction = Tables.Instruction;
const Decode = @import("decode.zig");

pub fn disassemble(bytecode: []const u8, allocator: Allocator) ![]const u8 {
    var disassembly = try std.ArrayList(u8).initCapacity(allocator, bytecode.len * 8);

    try disassemble_bytecode(bytecode, &disassembly);

    return disassembly.toOwnedSlice();
}

fn disassemble_bytecode(bytecode: []const u8, disassembly: *std.ArrayList(u8)) !void {
    try disassembly.appendSlice("bits 16\n\n");

    var inst_ptr: usize = 0;

    var instruction: Instruction = undefined;
    while (inst_ptr < bytecode.len) : (try disassembly.append('\n')) {
        instruction = try Decode.decode_next_instruction(bytecode[inst_ptr..], 0, 0);
        inst_ptr += instruction.bytes;
        try instruction_to_string(&instruction, disassembly);
    }
    _ = disassembly.pop(); // remove the last \n
}

pub fn instruction_to_string(instruction: *Instruction, disassembly: *std.ArrayList(u8)) !void {
    if (instruction.flags & LOCK_FLAG != 0) {
        if (instruction.op_code == .xchg_reg_acc or instruction.op_code == .xchg_reg_rm) {
            const temp_op: Operand = instruction.operands[0];
            instruction.operands[0] = instruction.operands[1];
            instruction.operands[1] = temp_op;
        }
        try disassembly.appendSlice("lock ");
    }

    if (instruction.flags & REP_FLAG != 0) {
        const z = instruction.flags & Z_FLAG;
        try disassembly.appendSlice(if (z != 0) "rep " else "repne ");
    }

    try disassembly.appendSlice(op_to_str_map[@as(usize, @intFromEnum(instruction.op_code))]);

    if (instruction.flags & REP_FLAG != 0) {
        const w = instruction.flags & W_FLAG;
        try disassembly.appendSlice(if (w == 1) "w" else "b");
    }

    if (instruction.operands[0] != .none or instruction.operands[1] != .none) {
        try disassembly.appendSlice(" ");
    }

    try appendOperands(instruction, disassembly);
}

fn appendOperands(instruction: *Instruction, disassembly: *std.ArrayList(u8)) !void {
    var buffer: [1024]u8 = undefined;

    var seperator: []const u8 = "";
    for (instruction.operands) |operand| {
        try disassembly.appendSlice(seperator);
        if (instruction.operands[1] != .none and instruction.operands[0] != .none) {
            seperator = ", ";
        }

        switch (operand) {
            .register => |r| {
                const register: Tables.Registers = @enumFromInt(r);
                try disassembly.appendSlice(@tagName(register));
            },
            .immediate => |i| {
                if (instruction.flags & REL_JUMP_FLAG != 0) {
                    const value: i16 = @bitCast(i);
                    var sign: []const u8 = undefined;
                    if (value < 0) {
                        sign = "-";
                    } else {
                        sign = "+";
                    }
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "${s}{d}", .{ sign, @abs(value + instruction.bytes) }));
                } else {
                    const value: u16 = @bitCast(i);
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "{d}", .{value}));
                }
            },
            .memory => |m| {
                const displacement = m.displacement;
                var sign: []const u8 = undefined;
                if (displacement < 0) {
                    sign = "-";
                } else {
                    sign = "+";
                }

                if (instruction.flags & FAR_FLAG != 0) {
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "far ", .{}));
                }

                if (instruction.operands[0] != .register) {
                    const w: usize = @intCast(instruction.flags & 1);
                    const qualifier = [_][]const u8{ "byte ", "word " };
                    try disassembly.appendSlice(qualifier[w]);
                }

                if (instruction.flags & SEGMENT_OVERRIDE_FLAG != 0) {
                    const sr: Tables.Registers = @enumFromInt(instruction.segment_override);
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "{s}:", .{@tagName(sr)}));
                }

                const effective_addr = Tables.EffectiveAddressStr[m.ptr];
                if (m.is_direct) {
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "[{d}]", .{displacement}));
                } else if (displacement == 0) {
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "[{s}]", .{effective_addr}));
                } else {
                    try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "[{s} {s} {d}]", .{ effective_addr, sign, @abs(displacement) }));
                }
            },
            .explicit_segment => |s| {
                try disassembly.appendSlice(try std.fmt.bufPrint(&buffer, "{d}:{d}", .{ s.segment, s.displacement }));
            },
            .none => continue,
        }
    }
}

const test_struct = struct {
    input: []const u8,
    output: []const u8,
};

test "mov" {
    const test_cases = [_]test_struct{
        // reg, reg
        .{ .input = &[_]u8{ 137, 217 }, .output = "bits 16\n\nmov cx, bx" },
        .{ .input = &[_]u8{ 136, 229 }, .output = "bits 16\n\nmov ch, ah" },
        .{ .input = &[_]u8{ 137, 222 }, .output = "bits 16\n\nmov si, bx" },
        .{ .input = &[_]u8{ 137, 251, 136, 200 }, .output = "bits 16\n\nmov bx, di\nmov al, cl" },
        // reg, rm
        .{ .input = &[_]u8{ 0b10001011, 0b01001010, 0b00000010 }, .output = "bits 16\n\nmov cx, [bp + si + 2]" },
        .{ .input = &[_]u8{ 0b10001000, 0b01101110, 0b00000000 }, .output = "bits 16\n\nmov byte [bp], ch" },
        .{ .input = &[_]u8{ 0b10001001, 0b10001110, 0b00000001, 0b00000000 }, .output = "bits 16\n\nmov word [bp + 1], cx" },
        .{ .input = &[_]u8{ 0b10001011, 0b01000001, 0b11011011 }, .output = "bits 16\n\nmov ax, [bx + di - 37]" },
        .{ .input = &[_]u8{ 0b10001011, 0b00011011 }, .output = "bits 16\n\nmov bx, [bp + di]" },
        .{ .input = &[_]u8{ 0b10001001, 0b10001100, 0b11010100, 0b11111110 }, .output = "bits 16\n\nmov word [si - 300], cx" },
        .{ .input = &[_]u8{ 0b10100011, 0b00001111, 0b00000000 }, .output = "bits 16\n\nmov word [15], ax" },
        .{ .input = &[_]u8{ 0b10001011, 0b00101110, 0b00000101, 0b00000000 }, .output = "bits 16\n\nmov bp, [5]" },
        // im, reg
        .{ .input = &[_]u8{ 0b10111001, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov cx, 257" },
        .{ .input = &[_]u8{ 0b10110001, 0b00000001 }, .output = "bits 16\n\nmov cl, 1" },
        // im, rm
        .{ .input = &[_]u8{ 0b11000110, 0b00000011, 0b00000111 }, .output = "bits 16\n\nmov byte [bp + di], 7" },
        .{ .input = &[_]u8{ 0b11000111, 0b00000011, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov word [bp + di], 257" },
        // mem_acc
        .{ .input = &[_]u8{ 0b10100001, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov ax, [257]" },
        .{ .input = &[_]u8{ 0b10100011, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov word [257], ax" },
        .{ .input = &[_]u8{ 0b10100010, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov byte [257], al" },
        // rm sr
        .{ .input = &[_]u8{ 0b10001110, 0b00000011 }, .output = "bits 16\n\nmov es, [bp + di]" },
        .{ .input = &[_]u8{ 0b10001100, 0b00001011 }, .output = "bits 16\n\nmov word [bp + di], cs" },
    };
    try test_inputs(&test_cases, false);
}

test "push" {
    const test_cases = [_]test_struct{
        // rm
        .{ .input = &[_]u8{ 0b11111111, 0b00110001 }, .output = "bits 16\n\npush word [bx + di]" },
        .{ .input = &[_]u8{ 0b11111111, 0b10110001, 0b00000001, 0b00000001 }, .output = "bits 16\n\npush word [bx + di + 257]" },
        // reg
        .{ .input = &[_]u8{0b01010000}, .output = "bits 16\n\npush ax" },
        // segment register
        .{ .input = &[_]u8{0b00010110}, .output = "bits 16\n\npush ss" },
    };
    try test_inputs(&test_cases, false);
}

test "pop" {
    const test_cases = [_]test_struct{
        // rm
        .{ .input = &[_]u8{ 0b10001111, 0b00000001 }, .output = "bits 16\n\npop word [bx + di]" },
        .{ .input = &[_]u8{ 0b10001111, 0b10000001, 0b00000001, 0b00000001 }, .output = "bits 16\n\npop word [bx + di + 257]" },
        // reg
        .{ .input = &[_]u8{0b01011000}, .output = "bits 16\n\npop ax" },
        // segment register
        .{ .input = &[_]u8{0b00010111}, .output = "bits 16\n\npop ss" },
    };
    try test_inputs(&test_cases, false);
}

test "xchg" {
    const test_cases = [_]test_struct{
        // reg rm
        .{ .input = &[_]u8{ 0b10000111, 0b10001001, 0b00000001, 0b00000001 }, .output = "bits 16\n\nxchg word [bx + di + 257], cx" },
        // acc
        .{ .input = &[_]u8{0b10010111}, .output = "bits 16\n\nxchg ax, di" },
    };
    try test_inputs(&test_cases, false);
}

test "in" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b11100100, 0b11001000 },
            .output = "bits 16\n\nin al, 200",
        },
        .{
            .input = &[_]u8{0b11101100},
            .output = "bits 16\n\nin al, dx",
        },
        .{
            .input = &[_]u8{0b11101101},
            .output = "bits 16\n\nin ax, dx",
        },
    };
    try test_inputs(&test_cases, false);
}

test "out" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b11100111, 0b00101100 },
            .output = "bits 16\n\nout 44, ax",
        },
        .{
            .input = &[_]u8{0b11101110},
            .output = "bits 16\n\nout dx, al",
        },
    };
    try test_inputs(&test_cases, false);
}

test "xlat" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{0b11010111},
            .output = "bits 16\n\nxlat",
        },
    };
    try test_inputs(&test_cases, false);
}

test "lea" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b10001101, 0b10000001, 0b10001100, 0b00000101 },
            .output = "bits 16\n\nlea ax, [bx + di + 1420]",
        },
        .{
            .input = &[_]u8{ 0b10001101, 0b01011110, 0b11001110 },
            .output = "bits 16\n\nlea bx, [bp - 50]",
        },
        .{
            .input = &[_]u8{ 0b10001101, 0b10100110, 0b00010101, 0b11111100 },
            .output = "bits 16\n\nlea sp, [bp - 1003]",
        },
        .{
            .input = &[_]u8{ 0b10001101, 0b01111000, 0b11111001 },
            .output = "bits 16\n\nlea di, [bx + si - 7]",
        },
    };
    try test_inputs(&test_cases, false);
}

test "lds" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b11000101, 0b10000001, 0b10001100, 0b00000101 },
            .output = "bits 16\n\nlds ax, [bx + di + 1420]",
        },
        .{
            .input = &[_]u8{ 0b11000101, 0b01011110, 0b11001110 },
            .output = "bits 16\n\nlds bx, [bp - 50]",
        },
        .{
            .input = &[_]u8{ 0b11000101, 0b10100110, 0b00010101, 0b11111100 },
            .output = "bits 16\n\nlds sp, [bp - 1003]",
        },
        .{
            .input = &[_]u8{ 0b11000101, 0b01111000, 0b11111001 },
            .output = "bits 16\n\nlds di, [bx + si - 7]",
        },
    };
    try test_inputs(&test_cases, false);
}

test "les" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b11000100, 0b10000001, 0b10001100, 0b00000101 },
            .output = "bits 16\n\nles ax, [bx + di + 1420]",
        },
        .{
            .input = &[_]u8{ 0b11000100, 0b01011110, 0b11001110 },
            .output = "bits 16\n\nles bx, [bp - 50]",
        },
        .{
            .input = &[_]u8{ 0b11000100, 0b10100110, 0b00010101, 0b11111100 },
            .output = "bits 16\n\nles sp, [bp - 1003]",
        },
        .{
            .input = &[_]u8{ 0b11000100, 0b01111000, 0b11111001 },
            .output = "bits 16\n\nles di, [bx + si - 7]",
        },
    };
    try test_inputs(&test_cases, false);
}

test "misc out instructions" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{0b10011111},
            .output = "bits 16\n\nlahf",
        },
        .{
            .input = &[_]u8{0b10011110},
            .output = "bits 16\n\nsahf",
        },
        .{
            .input = &[_]u8{0b10011100},
            .output = "bits 16\n\npushf",
        },
        .{
            .input = &[_]u8{0b10011101},
            .output = "bits 16\n\npopf",
        },
    };
    try test_inputs(&test_cases, false);
}

test "add" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b00000011, 0b01001110, 0b00000000 },
            .output = "bits 16\n\nadd cx, [bp]",
        },
        .{
            .input = &[_]u8{ 0b10000001, 0b011000100, 0b10001000, 0b00000001 },
            .output = "bits 16\n\nadd sp, 392",
        },
        .{
            .input = &[_]u8{ 0b00000100, 0b00001001 },
            .output = "bits 16\n\nadd al, 9",
        },
        .{
            .input = &[_]u8{ 0b00000000, 0b11000101 },
            .output = "bits 16\n\nadd ch, al",
        },
    };
    try test_inputs(&test_cases, false);
}

test "adc" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b00010011, 0b01001110, 0b00000000 },
            .output = "bits 16\n\nadc cx, [bp]",
        },
        .{
            .input = &[_]u8{ 0b10000001, 0b011010100, 0b10001000, 0b00000001 },
            .output = "bits 16\n\nadc sp, 392",
        },
        .{
            .input = &[_]u8{ 0b00010100, 0b00001001 },
            .output = "bits 16\n\nadc al, 9",
        },
        .{
            .input = &[_]u8{ 0b00010000, 0b11000101 },
            .output = "bits 16\n\nadc ch, al",
        },
    };
    try test_inputs(&test_cases, false);
}

test "inc" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{0b01000001},
            .output = "bits 16\n\ninc cx",
        },
        .{
            .input = &[_]u8{ 0b11111110, 0b10000110, 0b11101010, 0b00000011 },
            .output = "bits 16\n\ninc byte [bp + 1002]",
        },
        .{
            .input = &[_]u8{ 0b11111111, 0b10000011, 0b11000100, 0b11011000 },
            .output = "bits 16\n\ninc word [bp + di - 10044]",
        },
        .{
            .input = &[_]u8{ 0b11111111, 0b00000110, 0b10000101, 0b00100100 },
            .output = "bits 16\n\ninc word [9349]",
        },
    };
    try test_inputs(&test_cases, false);
}

test "sub" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b00101011, 0b01001110, 0b00000000 },
            .output = "bits 16\n\nsub cx, [bp]",
        },
        .{
            .input = &[_]u8{ 0b10000001, 0b011101100, 0b10001000, 0b00000001 },
            .output = "bits 16\n\nsub sp, 392",
        },
        .{
            .input = &[_]u8{ 0b00101100, 0b00001001 },
            .output = "bits 16\n\nsub al, 9",
        },
        .{
            .input = &[_]u8{ 0b00101000, 0b11000101 },
            .output = "bits 16\n\nsub ch, al",
        },
    };
    try test_inputs(&test_cases, false);
}

test "sbb" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b00011011, 0b01001110, 0b00000000 },
            .output = "bits 16\n\nsbb cx, [bp]",
        },
        .{
            .input = &[_]u8{ 0b10000001, 0b011011100, 0b10001000, 0b00000001 },
            .output = "bits 16\n\nsbb sp, 392",
        },
        .{
            .input = &[_]u8{ 0b00011100, 0b00001001 },
            .output = "bits 16\n\nsbb al, 9",
        },
        .{
            .input = &[_]u8{ 0b00011000, 0b11000101 },
            .output = "bits 16\n\nsbb ch, al",
        },
    };
    try test_inputs(&test_cases, false);
}

test "dec" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{0b01001001},
            .output = "bits 16\n\ndec cx",
        },
        .{
            .input = &[_]u8{ 0b11111110, 0b10001110, 0b11101010, 0b00000011 },
            .output = "bits 16\n\ndec byte [bp + 1002]",
        },
        .{
            .input = &[_]u8{ 0b11111111, 0b10001011, 0b11000100, 0b11011000 },
            .output = "bits 16\n\ndec word [bp + di - 10044]",
        },
        .{
            .input = &[_]u8{ 0b11111111, 0b00001110, 0b10000101, 0b00100100 },
            .output = "bits 16\n\ndec word [9349]",
        },
    };
    try test_inputs(&test_cases, false);
}

test "neg" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b11110110, 0b10011110, 0b11101010, 0b00000011 },
            .output = "bits 16\n\nneg byte [bp + 1002]",
        },
        .{
            .input = &[_]u8{ 0b11110111, 0b10011011, 0b11000100, 0b11011000 },
            .output = "bits 16\n\nneg word [bp + di - 10044]",
        },
        .{
            .input = &[_]u8{ 0b11110111, 0b00011110, 0b10000101, 0b00100100 },
            .output = "bits 16\n\nneg word [9349]",
        },
    };
    try test_inputs(&test_cases, false);
}

test "aam" {
    const test_cases = [_]test_struct{
        .{
            .input = &[_]u8{ 0b11010100, 0b00001010 },
            .output = "bits 16\n\naam",
        },
    };
    try test_inputs(&test_cases, false);
}

fn test_inputs(test_cases: []const test_struct, debug: bool) !void {
    for (test_cases, 0..) |case, i| {
        if (debug) {
            std.debug.print("Test[{d}]" ++ "--" ** 20 ++ "\n", .{i});
            std.debug.print("Input: {b}\n\n", .{case.input});
            std.debug.print("Expected output:\n{s}\n\n", .{case.output});
        }
        const output = try disassemble(case.input, std.testing.allocator);
        defer std.testing.allocator.free(output);
        if (debug) {
            std.debug.print("Output:\n{s}\n", .{output});
        }

        try testing.expectEqualSlices(u8, case.output, output);
    }
}
