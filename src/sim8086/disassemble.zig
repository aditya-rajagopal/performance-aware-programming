const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils");
const Tables = @import("tables.zig");
const assert = utils.assert;

pub const Disassembler = @This();

bytecode: []const u8,
disassembly: std.ArrayList(u8),

inst_ptr: usize = 0,

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

    while (self.inst_ptr < self.bytecode.len) : (try self.append("\n")) {
        const op = self.increment_ptr();
        const op_code = find_op_code(op);

        const location = @as(usize, @intCast(@intFromEnum(op_code)));

        try self.append(Tables.inst_to_string[location]);
        try self.append(" ");

        std.debug.print("op_code: {b} {s}\n", .{ op, @tagName(op_code) });
        switch (op_code) {
            .mov_rm_reg => try self.disassemble_mov_reg_rm(op),
            .mov_im_reg => try self.disassemble_mov_im_reg(op),
            .mov_im_rm => try self.disassemble_mov_im_rm(op),
            .mov_mem_acc => try self.disassemble_mov_mem_acc(op),
            else => unreachable,
        }
    }
    _ = self.disassembly.pop(); // remove the last \n
}

fn disassemble_mov_mem_acc(self: *Disassembler, op: u8) !void {
    const w = op & 1;
    const dir = (op >> 1) & 1;

    const addr = try self.parse_bytes_as_int(2);

    var strings: [2][]const u8 = undefined;
    var buffer: [32]u8 = undefined;
    const reg = [_][]const u8{ "al", "ax" };
    strings[0] = reg[w];
    strings[1] = try std.fmt.bufPrint(&buffer, "[{d}]", .{addr});

    try self.disassembly.appendSlice(strings[dir]);
    try self.disassembly.appendSlice(", ");
    try self.disassembly.appendSlice(strings[dir ^ 1]);
}

fn disassemble_mov_im_rm(self: *Disassembler, op: u8) !void {
    const w = op & 1;
    const payload = self.increment_ptr();
    const rm = payload & 0b111;
    const mod = payload >> 6;
    const qualifier = [_][]const u8{ "byte", "word" };
    // std.debug.print(
    //     "mov: w:{b}, mod:{b:0>2}, rm:{b:0>3} \n",
    //     .{ w, mod, rm },
    // );

    var buffer: [256]u8 = undefined;
    var buffer2: [256]u8 = undefined;
    var addr = try self.get_effective_addr(rm, mod, w, &buffer);
    const im_val = try self.parse_bytes_as_int(w + 1);
    addr = try std.fmt.bufPrint(&buffer2, "{s}, {s} {d}", .{ addr, qualifier[w], im_val });
    try self.disassembly.appendSlice(addr);
}

fn disassemble_mov_im_reg(self: *Disassembler, op: u8) !void {
    const w = (op >> 3) & 1;
    const offset = try self.parse_bytes_as_int(w + 1);
    const reg_str = Tables.Registers[op & 0b1111];
    var buffer: [1024]u8 = undefined;
    const line = try std.fmt.bufPrint(&buffer, "{s}, {d}", .{ reg_str, offset });
    try self.disassembly.appendSlice(line);
}

fn disassemble_mov_reg_rm(self: *Disassembler, op: u8) !void {
    const payload = self.increment_ptr();
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
    var strings: [2][]const u8 = undefined;

    switch (mode) {
        .mem_reg_mode => {
            const reg_indx: usize = (w << 3);

            strings[0] = Tables.Registers[reg_indx | reg];
            strings[1] = Tables.Registers[reg_indx | rm];
        },
        else => {
            const reg_index: usize = (w << 3) | reg;

            strings[0] = Tables.Registers[reg_index];
            var buffer: [256]u8 = undefined;
            strings[1] = try self.get_effective_addr(rm, mod, w, &buffer);
        },
    }
    try self.append(strings[d ^ 1]);
    try self.append(", ");
    try self.append(strings[d]);
}

fn get_effective_addr(self: *Disassembler, rm: usize, mod: usize, w: usize, buffer: []u8) ![]u8 {
    const effective_addr = Tables.EffectiveAddress[rm];
    var num_disp: usize = mod;
    var is_direct: bool = false;
    if (mod == 0 and rm == 0b110) {
        num_disp = @as(usize, @intCast(w)) + 1;
        is_direct = true;
    }

    const displacement = try self.parse_bytes_as_int(num_disp);
    var sign: []const u8 = undefined;
    if (displacement < 0) {
        sign = "-";
    } else {
        sign = "+";
    }
    if (is_direct) {
        return try std.fmt.bufPrint(buffer, "[{d}]", .{displacement});
    } else if (num_disp == 0 or displacement == 0) {
        return try std.fmt.bufPrint(buffer, "[{s}]", .{effective_addr});
    } else {
        return try std.fmt.bufPrint(buffer, "[{s} {s} {d}]", .{ effective_addr, sign, @abs(displacement) });
    }
}

fn parse_bytes_as_int(self: *Disassembler, num_bytes: usize) !i16 {
    assert(num_bytes <= 2, "Function not designed for more than 2 bytes as of now", .{});
    switch (num_bytes) {
        0 => return 0,
        1 => {
            assert(self.inst_ptr < self.bytecode.len, "Not enough bytes to read 8bit number", .{});
            const data = std.mem.bytesToValue(i8, self.bytecode[self.inst_ptr .. self.inst_ptr + 1]);
            // const data = self.increment_ptr();
            self.inst_ptr += 1;
            return @intCast(data);
        },
        2 => {
            assert(self.inst_ptr < self.bytecode.len - 1, "Not enough bytes to read 16bit number", .{});
            const data = std.mem.bytesToValue(i16, self.bytecode[self.inst_ptr .. self.inst_ptr + 2]);
            self.inst_ptr += 2;
            return data;
        },
        else => unreachable,
    }
}

fn find_op_code(op_bytecode: u8) Tables.instruction {
    inline for (std.meta.fields(Tables.instruction)) |f| {
        const value = f.value; // 0b10100
        const first_bit = value & -value; // 0b00100
        const ctz = std.math.log2(first_bit); // 2
        // std.debug.print("Field: {b:0>8}, op_code: {b:0>8}, res: {d}\n", .{ f.value, op_bytecode, ctz });
        if (f.value >> ctz == op_bytecode >> ctz) {
            return @enumFromInt(f.value);
        }
    }
    unreachable;
}

fn increment_ptr(self: *Disassembler) u8 {
    assert(self.inst_ptr < self.bytecode.len, "Exceeding bytecode length", .{});
    const out = self.bytecode[self.inst_ptr];
    self.inst_ptr += 1;
    return out;
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
        .{ .input = 0b10001000, .output = .mov_rm_reg },
        .{ .input = 0b11000110, .output = .mov_im_rm },
        .{ .input = 0b10110000, .output = .mov_im_reg },
        .{ .input = 0b10100000, .output = .mov_mem_acc },
    };

    const debug: bool = false;

    for (test_cases, 0..) |case, i| {
        if (debug) {
            std.debug.print("Test[{d}]" ++ "--" ** 20 ++ "\n", .{i});
            std.debug.print("Input: 0b{b:0>8}\n", .{case.input});
        }
        const op_code = find_op_code(case.input);
        try testing.expectEqual(case.output, op_code);
        if (debug) {
            std.debug.print("Output: {s}\n", .{@tagName(op_code)});
        }
    }
}

test "mov" {
    const test_cases = [_]test_struct{
        .{ .input = &[_]u8{ 137, 217 }, .output = "bits 16\n\nmov cx, bx" },
        .{ .input = &[_]u8{ 136, 229 }, .output = "bits 16\n\nmov ch, ah" },
        .{ .input = &[_]u8{ 137, 222 }, .output = "bits 16\n\nmov si, bx" },
        .{ .input = &[_]u8{ 0b10001011, 0b01001010, 0b00000010 }, .output = "bits 16\n\nmov cx, [bp + si + 2]" },
        .{ .input = &[_]u8{ 0b10001000, 0b01101110, 0b00000000 }, .output = "bits 16\n\nmov [bp], ch" },
        .{ .input = &[_]u8{ 0b10001001, 0b10001110, 0b00000001, 0b00000000 }, .output = "bits 16\n\nmov [bp + 1], cx" },
        .{ .input = &[_]u8{ 0b10001011, 0b00011011 }, .output = "bits 16\n\nmov bx, [bp + di]" },
        .{ .input = &[_]u8{ 0b10111001, 0b00000001, 0b00000000 }, .output = "bits 16\n\nmov cx, 1" },
        .{ .input = &[_]u8{ 0b10001011, 0b01000001, 0b11011011 }, .output = "bits 16\n\nmov ax, [bx + di - 37]" },
        .{ .input = &[_]u8{ 0b10001001, 0b10001100, 0b11010100, 0b11111110 }, .output = "bits 16\n\nmov [si - 300], cx" },
        .{ .input = &[_]u8{ 0b10100011, 0b00001111, 0b00000000 }, .output = "bits 16\n\nmov [15], ax" },
        .{ .input = &[_]u8{ 0b10001011, 0b00101110, 0b00000101, 0b00000000 }, .output = "bits 16\n\nmov bp, [5]" },
        .{ .input = &[_]u8{ 137, 251, 136, 200 }, .output = "bits 16\n\nmov bx, di\nmov al, cl" },
    };
    try test_inputs(&test_cases, false);
}

test "test" {
    const a: u8 = 0b11011011;
    std.debug.print("A: {d}, comp: {d}", .{ a, @as(i8, @bitCast(a)) });
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
