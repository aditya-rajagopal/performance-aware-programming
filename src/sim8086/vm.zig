pub const VM = @This();

// align(2) here so that we can address them as u16 and if we
// try to access odd indicies it will throw an error
flags: u16 = 0,
registers: [24]u8 align(2) = .{0} ** 24,
immediate_store: [2]u8 align(2) = .{0} ** 2,
memory: [65535]u8 align(2) = .{0} ** 65535,

const ResolvedOp = struct {
    ptr: ?*u8,
    offset: usize = 0,
    reg_name: ?[]const u8 = null,
};

const Flags = enum(u16) {
    C = 0x1,
    P = 0x4,
    A = 0x10,
    Z = 0x40,
    S = 0x80,
    T = 0x100,
    I = 0x200,
    D = 0x400,
    O = 0x800,
};

pub fn simulate(bytecode: []const u8, allocator: Allocator) ![]const u8 {
    var vm = VM{};

    var vm_out = try std.ArrayList(u8).initCapacity(allocator, bytecode.len * 20);
    defer vm_out.deinit();

    var inst_ptr: usize = 0;
    var instruction: Instruction = undefined;
    while (inst_ptr < bytecode.len) : (try vm_out.append('\n')) {
        instruction = try Decode.decode_next_instruction(bytecode[inst_ptr..], 0, 0);
        inst_ptr += instruction.bytes;

        try instruction_to_string(&instruction, &vm_out);

        try vm_out.appendSlice(" ; ");

        try vm.execute(instruction, &vm_out);
    }
    try vm.add_vm_state(&vm_out);
    try vm_out.appendSlice("  flags: ");
    try flag_to_str(vm.flags, &vm_out);
    return vm_out.toOwnedSlice();
}

fn execute(self: *VM, instruction: Instruction, vm_out: *std.ArrayList(u8)) !void {
    const op_code = op_to_code[@intFromEnum(instruction.op_code)];
    const w = instruction.flags & W_FLAG != 0;

    const destination: ResolvedOp = self.resolve_operand(instruction.operands[0], w);
    const source: ResolvedOp = self.resolve_operand(instruction.operands[1], w);

    var buffer: [1024]u8 = undefined;

    const dest: *u16 = @ptrFromInt(@intFromPtr(destination.ptr.?) - destination.offset);

    const initial_value: u16 = dest.*;
    const initial_flags: u16 = self.flags;
    if (w) {
        self.resolve_code(u16, op_code, destination, source);
    } else {
        self.resolve_code(u8, op_code, destination, source);
    }
    const final_value = dest.*;
    const final_flags: u16 = self.flags;

    if (final_value != initial_value) {
        try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "{s}: ", .{destination.reg_name.?}));
        try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "0x{x:0>4}->", .{initial_value}));
        try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "0x{x:0>4}", .{final_value}));
    }

    if (initial_flags != final_flags) {
        try print_flag_diff(initial_flags, final_flags, vm_out);
    }
}

fn resolve_code(self: *VM, comptime T: type, op_code: Code, dest: ResolvedOp, src: ResolvedOp) void {
    const type_info = @typeInfo(T);
    var sign_check_mask: T = 0;
    switch (type_info) {
        .Int => |i| {
            sign_check_mask |= 1 << @truncate(i.bits - 1);
        },
        else => @compileError("Cant use this code with non-int type"),
    }

    const dest_ptr: *T = @alignCast(@ptrCast(dest.ptr.?));
    const src_ptr: *T = @alignCast(@ptrCast(src.ptr.?));

    switch (op_code) {
        .mov => {
            dest_ptr.* = src_ptr.*;
        },
        .add,
        .cmp,
        .sub,
        => {
            var output: struct { T, u1 } = undefined;
            var overflow: bool = false;
            switch (op_code) {
                .add => {
                    output = @addWithOverflow(dest_ptr.*, src_ptr.*);
                    const check = (output[0] ^ dest_ptr.*) & (output[0] ^ src_ptr.*) & sign_check_mask;
                    overflow = check != 0;
                },
                .sub, .cmp => {
                    output = @subWithOverflow(dest_ptr.*, src_ptr.*);
                    const check = (output[0] ^ dest_ptr.*) & (~(output[0] ^ src_ptr.*)) & sign_check_mask;
                    overflow = check != 0;
                },
                else => unreachable,
            }

            if (op_code != .cmp) {
                dest_ptr.* = output[0];
            }

            if (overflow) {
                self.set_flag(.O);
            } else {
                self.unset_flag(.O);
            }

            if (output[1] == 1) {
                self.set_flag(.C);
            } else {
                self.unset_flag(.C);
            }

            if (output[0] == 0) {
                self.set_flag(.Z);
            } else {
                self.unset_flag(.Z);
            }
            if (output[0] & sign_check_mask != 0) {
                self.set_flag(.S);
            } else {
                self.unset_flag(.S);
            }

            if (T == u16) {
                const low_bits: *u8 = @alignCast(@ptrCast(&output[0]));
                const num_low_set = @popCount(low_bits.*);
                if (num_low_set % 2 == 0) {
                    self.set_flag(.P);
                } else {
                    self.unset_flag(.P);
                }
            }
        },
        else => unreachable,
    }
}

fn resolve_operand(self: *VM, operand: Operand, w: bool) ResolvedOp {
    _ = w;
    switch (operand) {
        .none => return .{ .ptr = null },
        .register => |r| {
            if (r < 8) {
                const pos = r / 4;
                const reg_index = (r % 4);
                const reg: Register = @enumFromInt(reg_index + 8);
                return .{ .ptr = &self.registers[reg_index * 2 + pos], .reg_name = @tagName(reg), .offset = pos };
            } else {
                const reg_index: usize = r - 8;
                const reg: Register = @enumFromInt(r);
                return .{ .ptr = &self.registers[reg_index * 2], .reg_name = @tagName(reg) };
            }
        },
        .immediate => |i| {
            const imm_ptr: *u16 = @alignCast(@ptrCast(&self.immediate_store));
            imm_ptr.* = i;
            return .{ .ptr = &self.immediate_store[0] };
        },
        .memory => unreachable,
        .explicit_segment => unreachable,
    }
}

fn print_flag_diff(initial_flags: u16, final_flags: u16, vm_out: *std.ArrayList(u8)) !void {
    try vm_out.appendSlice(" flags: ");
    try flag_to_str(initial_flags, vm_out);
    try vm_out.appendSlice("->");
    try flag_to_str(final_flags, vm_out);
}

fn flag_to_str(flags: u16, vm_out: *std.ArrayList(u8)) !void {
    inline for (std.meta.fields(Flags)) |f| {
        if (f.value & flags != 0) {
            try vm_out.appendSlice(f.name);
        }
    }
}

fn add_vm_state(self: *VM, vm_out: *std.ArrayList(u8)) !void {
    try vm_out.appendSlice("\nFinal State:\n");
    var buffer: [1024]u8 = undefined;
    var i: usize = 0;
    while (i < self.registers.len) : (i += 2) {
        const reg_type: Register = @enumFromInt(i / 2 + 8);
        const reg: u16 = @as(*u16, @alignCast(@ptrCast(&self.registers[i]))).*;
        if (reg != 0) {
            try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "\t{s}: 0x{x:0>4} ({d})\n", .{ @tagName(reg_type), reg, reg }));
        }
    }
}

fn set_flag(self: *VM, flag: Flags) void {
    self.flags |= @intFromEnum(flag);
}

fn unset_flag(self: *VM, flag: Flags) void {
    self.flags &= ~@intFromEnum(flag);
}

test "random" {
    var out = std.ArrayList(u8).init(testing.allocator);
    defer out.deinit();
    try flag_to_str(0x44, &out);
    std.debug.print("Output: {s}", .{out.items});
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils");
const assert = utils.assert;
const Tables = @import("tables.zig");
const op_to_code = Tables.op_to_code;
const Operand = Tables.Operand;
const Register = Tables.Registers;
const Code = Tables.Code;
const REP_FLAG = Tables.REP_FLAG;
const Z_FLAG = Tables.Z_FLAG;
const W_FLAG = Tables.W_FLAG;
const REL_JUMP_FLAG = Tables.REL_JUMP_FLAG;
const LOCK_FLAG = Tables.LOCK_FLAG;
const SEGMENT_OVERRIDE_FLAG = Tables.SEGMENT_OVERRIDE_FLAG;
const FAR_FLAG = Tables.FAR_FLAG;
const Instruction = Tables.Instruction;
const Decode = @import("decode.zig");
const instruction_to_string = @import("disassemble.zig").instruction_to_string;
