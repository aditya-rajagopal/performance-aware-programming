const std = @import("std");

pub const instruction = enum(u8) {
    mov_reg_reg = 0b10001000,
    _,
};

pub const inst_to_string = std.enums.directEnumArrayDefault(
    instruction,
    []const u8,
    "unknown",
    256,
    .{
        .mov_reg_reg = "mov",
    },
);

/// This is for when MOD = 0b11
/// to index into this field you can do ( W << 3 ) | REG
pub const Registers: [16][]const u8 = .{
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

/// When MOD != 0b11
/// to index into this you can do (MOD << 3) | REG
pub const EffectiveAddress = .{};

pub const Mode = enum(u2) {
    mem_no_disp = 0b00,
    mem_8_bit_disp = 0b01,
    mem_16_bit_disp = 0b10,
    mem_reg_mode = 0b11,
};
