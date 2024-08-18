const Tables = @This();

pub const InstFieldType = enum(u8) {
    S,
    W,
    D,
    V,
    Z,
    MOD,
    REG,
    SR,
    RM,
    DATA_LO,
    DATA_HI,
    DISP_HI,
    DISP_LO,

    LITERAL,
    null_field,
};

pub const Registers = enum(u8) {
    A,
    C,
    D,
    B,
    SP,
    BP,
    SI,
    DI,
    // Segment registers
    ES,
    CS,
    SS,
    DS,
};

pub const InstFieldInfo = struct { // 4bytes
    inst_type: InstFieldType = .null_field,
    num_bits: u8 = 0,
    /// position in bits (how much to shift by)
    position: u8 = 0,
    /// Some info you might need to process the field_type. eg the bit opcode value
    payload: u8 = 0,
};

pub const Operation = enum(u8) {
    mov_rm_reg,
    mov_im_rm,
    mov_im_reg,
    mov_mem_acc,
    mov_acc_mem,
    mov_rm_sr,
    add,
};

pub const Code = enum(u8) {
    mov,
    add,
    unknown,
};

fn comptime_literal(comptime op_literal: []const u8) InstFieldInfo {
    const value = std.fmt.parseInt(u8, op_literal, 2) catch unreachable;
    return .{
        .inst_type = .LITERAL,
        .num_bits = op_literal.len,
        .position = 8 - op_literal.len,
        .payload = value,
    };
}

const D = InstFieldInfo{ .inst_type = .D, .num_bits = 1 };
const W = InstFieldInfo{ .inst_type = .W, .num_bits = 1 };
const MOD = InstFieldInfo{ .inst_type = .MOD, .num_bits = 2 };
const REG = InstFieldInfo{ .inst_type = .REG, .num_bits = 3 };
const RM = InstFieldInfo{ .inst_type = .RM, .num_bits = 3 };
const SR = InstFieldInfo{ .inst_type = .SR, .num_bits = 2 };
const DATA_LO = InstFieldInfo{ .inst_type = .DATA_LO, .num_bits = 0 };
const DATA_HI_OPT = InstFieldInfo{ .inst_type = .DATA_HI, .num_bits = 0, .payload = 0 };
const DATA_HI = InstFieldInfo{ .inst_type = .DATA_HI, .num_bits = 0, .payload = 1 };
const DISP_LO = InstFieldInfo{ .inst_type = .DISP_LO, .num_bits = 0 };
const DISP_HI_OPT = InstFieldInfo{ .inst_type = .DISP_HI, .num_bits = 0, .payload = 0 };
const DISP_HI = InstFieldInfo{ .inst_type = .DISP_HI, .num_bits = 0, .payload = 1 };

fn Set(comptime field_type: InstFieldType, comptime payload: u8) InstFieldInfo {
    return InstFieldInfo{
        .inst_type = field_type,
        .payload = payload,
    };
}

pub const op_to_code_map = std.enums.directEnumArrayDefault(
    Operation,
    Code,
    .unknown,
    256,
    .{
        .mov_rm_reg = .mov,
        .mov_im_rm = .mov,
        .mov_im_reg = .mov,
        .mov_mem_acc = .mov,
        .mov_acc_mem = .mov,
        .mov_rm_sr = .mov,
        .add = .add,
    },
);

pub const instruction_map = std.enums.directEnumArrayDefault(
    Operation,
    []const InstFieldInfo,
    null,
    0,
    .{
        .mov_rm_reg = &[_]InstFieldInfo{ comptime_literal("100010"), D, W, MOD, REG, RM },
        .mov_im_reg = &[_]InstFieldInfo{ comptime_literal("1011"), W, REG, DATA_LO, DATA_HI_OPT, Set(.D, 1) },
        .mov_im_rm = &[_]InstFieldInfo{ comptime_literal("1100011"), W, MOD, comptime_literal("000"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .mov_mem_acc = &[_]InstFieldInfo{
            comptime_literal("1010000"),
            W,
            DISP_LO,
            DISP_HI,
            Set(.D, 1), // We are moving into the accumulator
            Set(.REG, 0b000), // accumulator is always ax or al
            Set(.MOD, 0b00), // Make this instruction behave like a direct address
            Set(.RM, 0b110),
        },
        .mov_acc_mem = &[_]InstFieldInfo{
            comptime_literal("1010001"),
            W,
            DISP_LO,
            DISP_HI,
            Set(.D, 0),
            Set(.REG, 0b000),
            Set(.MOD, 0b00),
            Set(.RM, 0b110),
        },
        .mov_rm_sr = &[_]InstFieldInfo{
            comptime_literal("100011"),
            D,
            comptime_literal("0"),
            MOD,
            comptime_literal("0"),
            SR,
            RM,
            Set(.W, 1),
        },
        .add = &[_]InstFieldInfo{
            comptime_literal("000000"),
            D,
            W,
            MOD,
            REG,
            RM,
        },
    },
);

pub const EffectiveAddressExpression = struct {
    is_direct: bool,
    ptr: u3,
    displacement: i16,
};

pub const Operand = union(enum) {
    memory: EffectiveAddressExpression,
    register: u32,
    immediate: u16,
    none: void,
};

pub const Instruction = struct {
    op_code: Code = .unknown,
    flags: u8 = 0, // 0000 000W
    bytes: u8 = 0, // number of bytes to read for this op
    operands: [2]Operand = [_]Operand{ .none, .none }, // the first and second operand that this op works on.
};

test "operation_pattern_get" {
    const data = [_]u8{ 0b10001011, 0b01001010, 0b00000001, 0b111111 };
    _ = data;
}

pub const instruction_code = enum(u8) {
    mov_rm_reg = 0b10001000,
    mov_im_rm = 0b11000110,
    mov_im_reg = 0b10110000,
    mov_mem_acc = 0b10100000, // mov_acc_mem = 0b10100010 is the opposite. Check 2nd bit for direction
    add = 0b00000000,
    _,
};

pub const inst_to_string = std.enums.directEnumArrayDefault(
    instruction_code,
    []const u8,
    "unknown",
    256,
    .{
        .mov_rm_reg = "mov",
        .mov_im_rm = "mov",
        .mov_im_reg = "mov",
        .mov_mem_acc = "mov",
        .add = "add",
    },
);

/// to index into this field you can do ( W << 3 ) | REG
pub const RegistersStrings = [_][]const u8{
    "al",
    "cl",
    "dl",
    "bl",
    "ah",
    "ch",
    "dh",
    "bh",
    "ax",
    "cx",
    "dx",
    "bx",
    "sp",
    "bp",
    "si",
    "di",
};

/// to index into this you can index into this array using the R/M field
/// index 7 is special when RM is 00 so keep that in mind
pub const EffectiveAddress = [_][]const u8{
    "bx + si", // 000
    "bx + di", // 001
    "bp + si", // 010
    "bp + di", // 011
    "si", // 100
    "di", // 101
    "bp", // 110
    "bx", // 111
};

pub const Mode = enum(u2) {
    mem_no_disp = 0b00,
    mem_8_bit_disp = 0b01,
    mem_16_bit_disp = 0b10,
    mem_reg_mode = 0b11,
};

const std = @import("std");
const assert = @import("utils").assert;
