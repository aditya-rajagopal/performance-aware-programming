const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils");
const assert = utils.assert;
const Tables = @import("tables.zig");
const Decode = @import("decode.zig");

pub const Disassembler = @This();

bytecode: []const u8,
disassembly: std.ArrayList(u8),

inst_ptr: usize = 0,
disassembly_ptr: usize = 0,

pub fn init(bytecode: []const u8, allocator: Allocator) Disassembler {
    return .{
        .bytecode = bytecode,
        .disassembly = std.ArrayList(u8).init(allocator),
    };
}

pub fn append(self: *Disassembler, slice: []const u8) !void {
    try self.disassembly.appendSlice(slice);
}

pub fn disassemble(bytecode: []const u8, allocator: Allocator) ![]const u8 {
    var disassembler = Disassembler.init(bytecode, allocator);

    try disassembler.disassemble_bytecode();

    return disassembler.disassembly.toOwnedSlice();
}

fn disassemble_bytecode(self: *Disassembler) !void {
    try self.append("bits 16\n\n");
    self.disassembly_ptr = self.disassembly.items.len - 1;

    while (self.inst_ptr < self.bytecode.len) : (try self.append("\n")) {
        const instruction = try Decode.decode_next_instruction(self.bytecode[self.inst_ptr..]);
        self.inst_ptr += instruction.bytes;

        try self.append(@tagName(instruction.op_code));
        try self.append(" ");

        try self.appendOperand(instruction.operands[0], instruction.flags, false);

        if (instruction.operands[1] != .none and instruction.operands[0] != .none) {
            try self.append(", ");
        }

        try self.appendOperand(instruction.operands[1], instruction.flags, instruction.operands[0] == .none);
        std.debug.print("Bytecode decoded: {b:0>8}\n", .{self.bytecode[self.inst_ptr - instruction.bytes .. self.inst_ptr]});
        std.debug.print("Decoded instruction: {s} \n", .{self.disassembly.items[self.disassembly_ptr + 1 ..]});
        self.disassembly_ptr = self.disassembly.items.len;
    }
    _ = self.disassembly.pop(); // remove the last \n
}

fn appendOperand(self: *Disassembler, operand: Tables.Operand, flags: u8, mem_qualifier: bool) !void {
    const qualifier = [_][]const u8{ "", "byte ", "word " };
    var buffer: [1024]u8 = undefined;

    switch (operand) {
        .register => |r| {
            const register: Tables.Registers = @enumFromInt(r);
            try self.append(@tagName(register));
        },
        .immediate => |i| {
            const value: u16 = @bitCast(i);
            const dest_mem_mask: u8 = (flags >> 1) & 1;
            const w: usize = @intCast(flags & 1);
            try self.append(try std.fmt.bufPrint(&buffer, "{s}{d}", .{ qualifier[(w + 1) * dest_mem_mask], value }));
        },
        .memory => |m| {
            const displacement = m.displacement;
            var sign: []const u8 = undefined;
            if (displacement < 0) {
                sign = "-";
            } else {
                sign = "+";
            }
            if (mem_qualifier) {
                const w: usize = @intCast(flags & 1);
                try self.append(qualifier[w + 1]);
            }
            const effective_addr = Tables.EffectiveAddress[m.ptr];
            if (m.is_direct) {
                try self.append(try std.fmt.bufPrint(&buffer, "[{d}]", .{displacement}));
            } else if (displacement == 0) {
                try self.append(try std.fmt.bufPrint(&buffer, "[{s}]", .{effective_addr}));
            } else {
                try self.append(try std.fmt.bufPrint(&buffer, "[{s} {s} {d}]", .{ effective_addr, sign, @abs(displacement) }));
            }
        },
        .none => return,
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
        .{ .input = &[_]u8{ 0b10001000, 0b01101110, 0b00000000 }, .output = "bits 16\n\nmov [bp], ch" },
        .{ .input = &[_]u8{ 0b10001001, 0b10001110, 0b00000001, 0b00000000 }, .output = "bits 16\n\nmov [bp + 1], cx" },
        .{ .input = &[_]u8{ 0b10001011, 0b01000001, 0b11011011 }, .output = "bits 16\n\nmov ax, [bx + di - 37]" },
        .{ .input = &[_]u8{ 0b10001011, 0b00011011 }, .output = "bits 16\n\nmov bx, [bp + di]" },
        .{ .input = &[_]u8{ 0b10001001, 0b10001100, 0b11010100, 0b11111110 }, .output = "bits 16\n\nmov [si - 300], cx" },
        .{ .input = &[_]u8{ 0b10100011, 0b00001111, 0b00000000 }, .output = "bits 16\n\nmov [15], ax" },
        .{ .input = &[_]u8{ 0b10001011, 0b00101110, 0b00000101, 0b00000000 }, .output = "bits 16\n\nmov bp, [5]" },
        // im, reg
        .{ .input = &[_]u8{ 0b10111001, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov cx, 257" },
        .{ .input = &[_]u8{ 0b10110001, 0b00000001 }, .output = "bits 16\n\nmov cl, 1" },
        // im, rm
        .{ .input = &[_]u8{ 0b11000110, 0b00000011, 0b00000111 }, .output = "bits 16\n\nmov [bp + di], byte 7" },
        .{ .input = &[_]u8{ 0b11000111, 0b00000011, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov [bp + di], word 257" },
        // mem_acc
        .{ .input = &[_]u8{ 0b10100001, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov ax, [257]" },
        .{ .input = &[_]u8{ 0b10100011, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov [257], ax" },
        .{ .input = &[_]u8{ 0b10100010, 0b00000001, 0b00000001 }, .output = "bits 16\n\nmov [257], al" },
        // rm sr
        .{ .input = &[_]u8{ 0b10001110, 0b00000011 }, .output = "bits 16\n\nmov es, [bp + di]" },
        .{ .input = &[_]u8{ 0b10001100, 0b00001011 }, .output = "bits 16\n\nmov [bp + di], cs" },
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
        .{ .input = &[_]u8{ 0b10000111, 0b10001001, 0b00000001, 0b00000001 }, .output = "bits 16\n\nxchg cx, [bx + di + 257]" },
        // acc
        .{ .input = &[_]u8{0b10010111}, .output = "bits 16\n\nxchg ax, di" },
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
