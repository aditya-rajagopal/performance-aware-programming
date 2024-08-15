const Tables = @This();

pub const instruction = enum(u8) {
    mov_rm_reg = 0b10001000,
    mov_im_rm = 0b11000110,
    mov_im_reg = 0b10110000,
    mov_mem_acc = 0b10100000, // mov_acc_mem = 0b10100010 is the opposite. Check 2nd bit for direction
    _,
};

pub const inst_to_string = std.enums.directEnumArrayDefault(
    instruction,
    []const u8,
    "unknown",
    256,
    .{
        .mov_rm_reg = "mov",
        .mov_im_rm = "mov",
        .mov_im_reg = "mov",
        .mov_mem_acc = "mov",
    },
);

/// to index into this field you can do ( W << 3 ) | REG
pub const Registers = [_][]const u8{
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
