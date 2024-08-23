pub const VM = @This();

// align(2) here so that we can address them as u16 and if we
// try to access odd indicies it will throw an error
registers: [24]u8 align(2) = .{0} ** 24,
immediate_store: [2]u8 align(2) = .{0} ** 2,
memory: [65535]u8 align(2) = .{0} ** 65535,

const ResolvedOp = struct {
    ptr: ?*u8,
    offset: usize = 0,
    reg_name: ?[]const u8 = null,
};

pub fn simulate(bytecode: []const u8, allocator: Allocator) !void {
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
    std.debug.print("VM output:\n{s}", .{vm_out.items});
}

fn execute(self: *VM, instruction: Instruction, vm_out: *std.ArrayList(u8)) !void {
    const op_code = op_to_code[@intFromEnum(instruction.op_code)];
    const w = instruction.flags & W_FLAG != 0;

    const destination: ResolvedOp = self.resolve(instruction.operands[0], w);
    const source: ResolvedOp = self.resolve(instruction.operands[1], w);

    var buffer: [1024]u8 = undefined;

    switch (op_code) {
        .mov => {
            const dest: *u16 = @ptrFromInt(@intFromPtr(destination.ptr.?) - destination.offset);

            try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "{s}: ", .{destination.reg_name.?}));
            try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "0x{x:0>4}->", .{dest.*}));

            if (w) {
                const dest_ptr: *u16 = @alignCast(@ptrCast(destination.ptr.?));
                const source_ptr: *u16 = @alignCast(@ptrCast(source.ptr.?));
                dest_ptr.* = source_ptr.*;
            } else {
                destination.ptr.?.* = source.ptr.?.*;
            }
            try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "0x{x:0>4}", .{dest.*}));
        },
        else => unreachable,
    }
}

fn resolve(self: *VM, operand: Operand, w: bool) ResolvedOp {
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

fn add_vm_state(self: *VM, vm_out: *std.ArrayList(u8)) !void {
    try vm_out.appendSlice("\nFinal State:\n");
    var buffer: [1024]u8 = undefined;
    var i: usize = 0;
    while (i < self.registers.len) : (i += 2) {
        const reg_type: Register = @enumFromInt(i / 2 + 8);
        const reg: u16 = @as(*u16, @alignCast(@ptrCast(&self.registers[i]))).*;
        try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "\t{s}: 0x{x:0>4} ({d})\n", .{ @tagName(reg_type), reg, reg }));
    }
}

test "random" {
    std.debug.print("Size of VM: {d}\n", .{@sizeOf(VM)});
    std.debug.print("Size of VM: {d}\n", .{@alignOf(VM)});
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
