pub const VM = @This();

// align(2) here so that we can address them as u16 and if we
// try to access odd indicies it will throw an error
flags: u16 = 0,

/// Return pointer to this when you have a null operand
null_memory: u8 = 0,

registers: [24]u8 align(2) = .{0} ** 24,
ip_register: u16 = 0,
immediate_store: [2]u8 align(2) = .{0} ** 2,

memory: [1024 * 1024]u8 align(2) = .{0} ** (1024 * 1024),
max_memory_accessed: usize = 0,

const ResolvedOp = struct {
    ptr: *u8,
    offset: usize = 0,
    reg_name: ?[]const u8 = null,
};

var vm = VM{};

pub fn simulate(
    bytecode: []const u8,
    allocator: Allocator,
    config: struct {
        verbose: bool = false,
        mem_dump: bool = false,
    },
) ![]const u8 {
    vm.ip_register = 0;
    @memcpy(vm.memory[0..bytecode.len], bytecode);
    const ip_boundry = bytecode.len;
    var vm_out: std.ArrayList(u8) = undefined;
    if (config.verbose) {
        vm_out = try std.ArrayList(u8).initCapacity(allocator, bytecode.len * 20);
    } else {
        vm_out = std.ArrayList(u8).init(allocator);
    }
    defer vm_out.deinit();
    var buffer: [1024]u8 = undefined;

    var instruction: Instruction = undefined;
    while (vm.ip_register < ip_boundry) {
        instruction = try Decode.decode_next_instruction(vm.memory[vm.ip_register..], 0, 0);
        const initial_ip: u16 = vm.ip_register;

        vm.ip_register += instruction.bytes;

        if (config.verbose) {
            try instruction_to_string(&instruction, &vm_out);
            try vm_out.appendSlice(" ; ");
        }

        try vm.execute(instruction, &vm_out, config.verbose);

        if (config.verbose) {
            try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, " ip: 0x{x:0>4}->0x{x:0>4}", .{ initial_ip, vm.ip_register }));
            try vm_out.append('\n');
        }
    }

    if (config.mem_dump) {
        try vm_out.appendSlice(vm.memory[0..vm.max_memory_accessed]);
    } else {
        try vm.add_vm_state(&vm_out);
    }

    return vm_out.toOwnedSlice();
}

fn execute(self: *VM, instruction: Instruction, vm_out: *std.ArrayList(u8), verbose: bool) !void {
    const op_code = op_to_code[@intFromEnum(instruction.op_code)];
    const w = instruction.flags & W_FLAG != 0;

    const destination: ResolvedOp = self.resolve_operand(0, instruction);
    const source: ResolvedOp = self.resolve_operand(1, instruction);

    var buffer: [1024]u8 = undefined;

    var initial_value: u16 = 0;
    var dest: *u16 = undefined;

    if (destination.reg_name) |_| {
        dest = @ptrFromInt(@intFromPtr(destination.ptr) - destination.offset);
        initial_value = dest.*;
    }

    const initial_flags: u16 = self.flags;
    if (w) {
        self.resolve_code(u16, op_code, destination, source);
    } else {
        self.resolve_code(u8, op_code, destination, source);
    }

    if (verbose) {
        if (destination.reg_name) |name| {
            const final_value = dest.*;

            if (final_value != initial_value) {
                try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "{s}: ", .{name}));
                try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "0x{x:0>4}->", .{initial_value}));
                try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "0x{x:0>4}", .{final_value}));
            }
        }

        const final_flags: u16 = self.flags;
        if (initial_flags != final_flags) {
            try print_flag_diff(initial_flags, final_flags, vm_out);
        }
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

    const dest_ptr: *T = @alignCast(@ptrCast(dest.ptr));
    var out_value: T = undefined;
    var overflow: bool = false;
    var is_carry: bool = false;

    switch (op_code) {
        .mov => {
            const src_ptr: *T = @alignCast(@ptrCast(src.ptr));
            dest_ptr.* = src_ptr.*;
            return;
        },
        .jne => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                if (self.flags & @intFromEnum(Flags.Z) == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .je => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                if (self.flags & @intFromEnum(Flags.Z) != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jl => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const SF = self.flags & @intFromEnum(Flags.S);
                const OF = self.flags & @intFromEnum(Flags.O);
                if (SF != 0 or OF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jle => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const SF = self.flags & @intFromEnum(Flags.S);
                const OF = self.flags & @intFromEnum(Flags.O);
                const ZF = self.flags & @intFromEnum(Flags.Z);
                if ((SF != 0 or OF != 0) or ZF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jg => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const SF = self.flags & @intFromEnum(Flags.S);
                const OF = self.flags & @intFromEnum(Flags.O);
                const ZF = self.flags & @intFromEnum(Flags.Z);
                if (((SF != 0) == (OF != 0)) and ZF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .ja => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const ZF = self.flags & @intFromEnum(Flags.Z);
                const CF = self.flags & @intFromEnum(Flags.C);
                if (ZF == 0 and CF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jb => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CF = self.flags & @intFromEnum(Flags.C);
                if (CF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jbe => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CF = self.flags & @intFromEnum(Flags.C);
                const ZF = self.flags & @intFromEnum(Flags.Z);
                if (CF != 0 or ZF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jcxz => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CX: *u16 = @alignCast(@ptrCast(&self.registers[(@intFromEnum(Registers.cx) - 8) * 2]));
                if (CX.* == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jnb => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CF = self.flags & @intFromEnum(Flags.C);
                if (CF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jnl => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const SF = self.flags & @intFromEnum(Flags.S);
                const OF = self.flags & @intFromEnum(Flags.O);
                if ((SF != 0) == (OF != 0)) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jo => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const OF = self.flags & @intFromEnum(Flags.O);
                if (OF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jno => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const OF = self.flags & @intFromEnum(Flags.O);
                if (OF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jp => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const PF = self.flags & @intFromEnum(Flags.P);
                if (PF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jnp => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const PF = self.flags & @intFromEnum(Flags.P);
                if (PF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .js => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const SF = self.flags & @intFromEnum(Flags.S);
                if (SF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .jns => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const SF = self.flags & @intFromEnum(Flags.S);
                if (SF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .loop => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CX: *u16 = @alignCast(@ptrCast(&self.registers[(@intFromEnum(Registers.cx) - 8) * 2]));
                CX.* -= 1;
                if (CX.* != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .loopz => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CX: *u16 = @alignCast(@ptrCast(&self.registers[(@intFromEnum(Registers.cx) - 8) * 2]));
                const ZF = self.flags & @intFromEnum(Flags.Z);
                CX.* -= 1;
                if (CX.* != 0 and ZF != 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .loopnz => {
            if (T == u8) {
                const displacement: i8 = @bitCast(dest_ptr.*);
                const CX: *u16 = @alignCast(@ptrCast(&self.registers[(@intFromEnum(Registers.cx) - 8) * 2]));
                const ZF = self.flags & @intFromEnum(Flags.Z);
                CX.* -= 1;
                if (CX.* != 0 and ZF == 0) {
                    self.ip_register = @intCast(@as(i32, @intCast(self.ip_register)) + displacement);
                }
            }
            return;
        },
        .add => {
            const src_ptr: *T = @alignCast(@ptrCast(src.ptr));
            const output = @addWithOverflow(dest_ptr.*, src_ptr.*);
            const check = (output[0] ^ dest_ptr.*) & (output[0] ^ src_ptr.*) & sign_check_mask;
            overflow = check != 0;
            is_carry = output[1] == 1;
            out_value = output[0];
            dest_ptr.* = output[0];
        },
        .adc => {
            const src_ptr: *T = @alignCast(@ptrCast(src.ptr));
            const carry = @intFromBool(self.flags & @intFromEnum(Flags.C) != 0);
            const output_pre = @addWithOverflow(dest_ptr.*, src_ptr.*);
            const check1 = (output_pre[0] ^ dest_ptr.*) & (output_pre[0] ^ src_ptr.*) & sign_check_mask;

            var output = @addWithOverflow(output_pre[0], carry);
            output[1] = @intFromBool(output[1] == 1 or output_pre[1] == 1);
            const check2 = (output[0] ^ output_pre[0]) & (output[0] ^ carry) & sign_check_mask;
            overflow = check1 != 0 or check2 != 0;
            is_carry = output[1] == 1;
            out_value = output[0];
            dest_ptr.* = output[0];
        },
        .inc => {
            const output = @addWithOverflow(dest_ptr.*, 1);
            const check = (output[0] ^ dest_ptr.*) & (output[0] ^ 1) & sign_check_mask;
            overflow = check != 0;
            out_value = output[0];
            dest_ptr.* = output[0];
        },
        .sub, .cmp => |code| {
            const src_ptr: *T = @alignCast(@ptrCast(src.ptr));
            const output = @subWithOverflow(dest_ptr.*, src_ptr.*);
            const check = (output[0] ^ dest_ptr.*) & (~(output[0] ^ src_ptr.*)) & sign_check_mask;
            overflow = check != 0;
            is_carry = output[1] == 1;
            out_value = output[0];

            if (code == .sub) {
                dest_ptr.* = output[0];
            }
        },
        .sbb => {
            const src_ptr: *T = @alignCast(@ptrCast(src.ptr));
            const carry: T = @intFromBool(self.flags & @intFromEnum(Flags.C) != 0);

            const output_pre = @subWithOverflow(dest_ptr.*, src_ptr.*);
            const check1 = (output_pre[0] ^ dest_ptr.*) & (~(output_pre[0] ^ src_ptr.*)) & sign_check_mask;

            var output = @subWithOverflow(output_pre[0], carry);
            output[1] = @intFromBool(output[1] == 1 or output_pre[1] == 1);
            const check2 = (output[0] ^ output_pre[0]) & (~(output[0] ^ carry)) & sign_check_mask;
            overflow = check1 != 0 or check2 != 0;
            is_carry = output[1] == 1;
            out_value = output[0];
            dest_ptr.* = output[0];
        },
        .dec => {
            const output = @subWithOverflow(dest_ptr.*, 1);
            const check = (output[0] ^ dest_ptr.*) & (~(output[0] ^ 1)) & sign_check_mask;
            overflow = check != 0;
            out_value = output[0];
            dest_ptr.* = output[0];
        },
        .neg => {
            const temp = ~dest_ptr.*;
            const output = @addWithOverflow(temp, 1);
            const check = (output[0] ^ dest_ptr.*) & sign_check_mask;
            overflow = check != 0;
            is_carry = output[1] == 1;
            out_value = output[0];
            dest_ptr.* = output[0];
        },
        inline else => unreachable,
    }

    const flag_pattern: []const FlagCheck = code_flags[@intFromEnum(op_code)];

    for (flag_pattern) |flag_| {
        var flag = flag_;
        switch (flag.tag) {
            .unset, .set => {},
            .result => {
                switch (flag.flag) {
                    .C => {
                        flag.set = is_carry;
                    },
                    .O => {
                        flag.set = overflow;
                    },
                    .Z => {
                        flag.set = out_value == 0;
                    },
                    .S => {
                        flag.set = out_value & sign_check_mask != 0;
                    },
                    .P => {
                        if (T == u16) {
                            const low_bits: *u8 = @alignCast(@ptrCast(&out_value));
                            const num_low_set = @popCount(low_bits.*);
                            flag.set = num_low_set % 2 == 0;
                        }
                    },
                    else => continue,
                }
            },
        }
        flag.resolve(&self.flags);
    }
}

fn resolve_operand(self: *VM, index: usize, instruction: Instruction) ResolvedOp {
    switch (instruction.operands[index]) {
        .none => return .{ .ptr = &self.null_memory },
        .register => |r| {
            if (r < 8) {
                const pos = r / 4;
                const reg_index = (r % 4);
                const reg: Registers = @enumFromInt(reg_index + 8);
                return .{ .ptr = &self.registers[reg_index * 2 + pos], .reg_name = @tagName(reg), .offset = pos };
            } else {
                const reg_index: usize = r - 8;
                const reg: Registers = @enumFromInt(r);
                return .{ .ptr = &self.registers[reg_index * 2], .reg_name = @tagName(reg) };
            }
        },
        .immediate => |i| {
            if (instruction.flags & REL_JUMP_FLAG != 0) {
                const imm_ptr: *i16 = @alignCast(@ptrCast(&self.immediate_store));
                imm_ptr.* = @bitCast(i);
                return .{ .ptr = &self.immediate_store[0] };
            } else {
                const imm_ptr: *u16 = @alignCast(@ptrCast(&self.immediate_store));
                imm_ptr.* = i;
                return .{ .ptr = &self.immediate_store[0] };
            }
        },
        .memory => |m| {
            const displacement = m.displacement;
            var sr: Registers = .ds;
            if (instruction.flags & SEGMENT_OVERRIDE_FLAG != 0) {
                sr = @enumFromInt(instruction.segment_override);
            }
            const sr_pos: usize = @intFromEnum(sr) - 8;
            const sr_value: *u16 = @alignCast(@ptrCast(&self.registers[sr_pos * 2]));
            var memory: u16 = 0;

            if (m.is_direct) {
                assert(displacement >= 0, "Negative displacement", .{});
                memory = @bitCast(displacement);
            } else {
                const effective_address = effective_address_map[m.ptr];
                memory = @as(*u16, @alignCast(@ptrCast(&self.registers[(@intFromEnum(effective_address[0]) - 8) * 2]))).*;
                if (effective_address.len > 1) {
                    memory += @as(*u16, @alignCast(@ptrCast(&self.registers[(@intFromEnum(effective_address[1]) - 8) * 2]))).*;
                }
                memory = @intCast(@as(i32, @intCast(memory)) + displacement);
            }

            var ptr: usize = sr_value.* << 4;
            ptr += memory;
            self.max_memory_accessed = @max(self.max_memory_accessed, ptr);
            return .{ .ptr = &self.memory[ptr] };
        },
        .explicit_segment => |e| {
            const displacement: u16 = @as(*u16, @alignCast(@ptrCast(&self.registers[(e.segment - 8) * 2]))).*;
            const ptr: usize = @intCast(@as(i32, @intCast(displacement)) + e.displacement);
            self.max_memory_accessed = @max(self.max_memory_accessed, ptr);
            return .{ .ptr = &self.memory[ptr] };
        },
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
        const reg_type: Registers = @enumFromInt(i / 2 + 8);
        const reg: u16 = @as(*u16, @alignCast(@ptrCast(&self.registers[i]))).*;
        if (reg != 0) {
            try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "\t{s}: 0x{x:0>4} ({d})\n", .{ @tagName(reg_type), reg, reg }));
        }
    }
    try vm_out.appendSlice(try std.fmt.bufPrint(&buffer, "\tip: 0x{x:0>4} ({d})\n", .{ self.ip_register, self.ip_register }));
    try vm_out.appendSlice("  flags: ");
    try flag_to_str(self.flags, vm_out);
}

test VM {
    std.debug.print("Size of VM: {d}\n", .{@sizeOf(VM)});
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils");
const assert = utils.assert;
const Tables = @import("tables.zig");
const op_to_code = Tables.op_to_code;
const code_flags = Tables.code_flags;
const effective_address_map = Tables.effective_address_map;
const Operand = Tables.Operand;
const Registers = Tables.Registers;
const Code = Tables.Code;
const Flags = Tables.Flags;
const FlagCheck = Tables.FlagCheck;
const NumFlags = Tables.NumFlags;
const set_flag = Tables.set_flag;
const unset_flag = Tables.unset_flag;
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
