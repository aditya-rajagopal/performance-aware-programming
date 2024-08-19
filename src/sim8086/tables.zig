const Tables = @This();

pub const InstFieldType = enum(u8) {
    // Single bit fields
    S,
    W,
    D,
    V,
    Z,

    // Information to decide operands
    MOD,
    REG,
    SR,
    RM,

    // Extra data stuff
    DATA_LO,
    DATA_HI,
    DISP_HI,
    DISP_LO,

    // Bit literal
    LITERAL,

    // Extra info needed
    FLAGS,
    null_field,
};

pub const Registers = enum(u8) {
    al,
    cl,
    dl,
    bl,
    ah,
    ch,
    dh,
    bh,
    ax,
    cx,
    dx,
    bx,
    sp,
    bp,
    si,
    di,
    // Segment registers
    es,
    cs,
    ss,
    ds,
};

pub const InstFieldInfo = struct { // 4bytes
    inst_type: InstFieldType = .null_field,
    num_bits: u8 = 0,
    /// position in bits (how much to shift by)
    position: u8 = 0,
    /// Some info you might need to process the field_type. eg the bit opcode value
    payload: u8 = 0,
};

fn literal(comptime op_literal: []const u8) InstFieldInfo {
    @setEvalBranchQuota(200000);
    const value = std.fmt.parseInt(u8, op_literal, 2) catch unreachable;
    return .{
        .inst_type = .LITERAL,
        .num_bits = op_literal.len,
        .position = 8 - op_literal.len,
        .payload = value,
    };
}

pub const RM_FORCED_W_REG = 0b1;

const D = InstFieldInfo{ .inst_type = .D, .num_bits = 1 };
const S = InstFieldInfo{ .inst_type = .S, .num_bits = 1 };
const W = InstFieldInfo{ .inst_type = .W, .num_bits = 1 };
const V = InstFieldInfo{ .inst_type = .V, .num_bits = 1 };
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
const FORCE_RM_WIDE = InstFieldInfo{ .inst_type = .FLAGS, .num_bits = 0, .payload = RM_FORCED_W_REG };

fn Flag(comptime flag: usize) InstFieldInfo {
    return InstFieldInfo{
        .inst_type = .FLAGS,
        .num_bits = 0,
        .payload = flag,
    };
}

fn Set(comptime field_type: InstFieldType, comptime payload: u8) InstFieldInfo {
    return InstFieldInfo{
        .inst_type = field_type,
        .payload = payload,
    };
}

pub const Operation = enum(u8) {
    mov_rm_reg,
    mov_im_rm,
    mov_im_reg,
    mov_mem_acc,
    mov_acc_mem,
    mov_rm_sr,
    push_rm,
    push_reg,
    push_seg,
    pop_rm,
    pop_reg,
    pop_seg,
    xchg_reg_rm,
    xch_reg_acc,
    in_fixed,
    in_var, // the variable port will be in dx even if W is 0
    out_fixed,
    out_var, // the variable port will be in dx even if W is 0
    xlat,
    lea,
    lds,
    les,
    lahf,
    sahf,
    pushf,
    popf,
    add_reg_rm,
    add_im_rm,
    add_im_acc,
    adc_reg_rm,
    adc_im_rm,
    adc_im_acc,
    inc_rm,
    inc_reg,
    aaa,
    daa,
    sub_reg_rm,
    sub_im_rm,
    sub_im_acc,
    sbb_reg_rm,
    sbb_im_rm,
    sbb_im_acc,
    dec_rm,
    dec_reg,
    neg,
    cmp_rm_reg,
    cmp_im_rm,
    cmp_im_acc,
    aas,
    das,
    mul,
    imul,
    aam,
    div,
    idiv,
    aad,
    cbw,
    cwd,
    not,
    shl,
    // sal,
    shr,
    sar,
    rol,
    ror,
    rcl,
    rcr,
};

pub const Code = enum(u8) {
    mov,
    push,
    pop,
    xchg,
    in,
    out,
    xlat,
    lea,
    lds,
    les,
    lahf,
    sahf,
    pushf,
    popf,
    add,
    adc,
    inc,
    aaa,
    daa,
    sub,
    sbb,
    dec,
    neg,
    cmp,
    aas,
    das,
    mul,
    imul,
    aam,
    div,
    idiv,
    aad,
    cbw,
    cwd,
    not,
    shl,
    // sal,
    shr,
    sar,
    rol,
    ror,
    rcl,
    rcr,
    unknown,
};

pub const op_to_code_map = std.enums.directEnumArrayDefault(Operation, Code, .unknown, 256, .{
    .mov_rm_reg = .mov,
    .mov_im_rm = .mov,
    .mov_im_reg = .mov,
    .mov_mem_acc = .mov,
    .mov_acc_mem = .mov,
    .mov_rm_sr = .mov,
    .push_rm = .push,
    .push_reg = .push,
    .push_seg = .push,
    .pop_rm = .pop,
    .pop_reg = .pop,
    .pop_seg = .pop,
    .xchg_reg_rm = .xchg,
    .xch_reg_acc = .xchg,
    .in_fixed = .in,
    .in_var = .in,
    .out_fixed = .out,
    .out_var = .out,
    .xlat = .xlat,
    .lea = .lea,
    .lds = .lds,
    .les = .les,
    .lahf = .lahf,
    .sahf = .sahf,
    .pushf = .pushf,
    .popf = .popf,
    .add_reg_rm = .add,
    .add_im_rm = .add,
    .add_im_acc = .add,
    .adc_reg_rm = .adc,
    .adc_im_rm = .adc,
    .adc_im_acc = .adc,
    .inc_rm = .inc,
    .inc_reg = .inc,
    .aaa = .aaa,
    .daa = .daa,
    .sub_reg_rm = .sub,
    .sub_im_rm = .sub,
    .sub_im_acc = .sub,
    .sbb_reg_rm = .sbb,
    .sbb_im_rm = .sbb,
    .sbb_im_acc = .sbb,
    .dec_rm = .dec,
    .dec_reg = .dec,
    .neg = .neg,
    .cmp_rm_reg = .cmp,
    .cmp_im_rm = .cmp,
    .cmp_im_acc = .cmp,
    .aas = .aas,
    .das = .das,
    .mul = .mul,
    .imul = .imul,
    .aam = .aam,
    .div = .div,
    .idiv = .idiv,
    .aad = .aad,
    .cbw = .cbw,
    .cwd = .cwd,
    .not = .not,
    .shl = .shl,
    // .sal = .sal,
    .shr = .shr,
    .sar = .sar,
    .rol = .rol,
    .ror = .ror,
    .rcl = .rcl,
    .rcr = .rcr,
});

fn GetInstructionMap(
    comptime E: type,
    comptime Data: type,
    comptime default: ?Data,
    comptime max_unused_slots: comptime_int,
    init_values: std.enums.EnumFieldStruct(E, Data, default),
) [std.enums.directEnumArrayLen(E, max_unused_slots)]Data {
    @setEvalBranchQuota(200000);
    return std.enums.directEnumArrayDefault(
        E,
        Data,
        default,
        max_unused_slots,
        init_values,
    );
}

pub const instruction_map = GetInstructionMap(
    Operation,
    []const InstFieldInfo,
    null,
    0,
    .{
        .mov_rm_reg = &[_]InstFieldInfo{ literal("100010"), D, W, MOD, REG, RM },
        .mov_im_reg = &[_]InstFieldInfo{ literal("1011"), W, REG, DATA_LO, DATA_HI_OPT, Set(.D, 1) },
        .mov_im_rm = &[_]InstFieldInfo{ literal("1100011"), W, MOD, literal("000"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .mov_mem_acc = &[_]InstFieldInfo{
            literal("1010000"),
            W,
            DISP_LO,
            DISP_HI,
            Set(.D, 1), // We are moving into the accumulator
            Set(.REG, 0b000), // accumulator is always ax or al
            Set(.MOD, 0b00), // Make this instruction behave like a direct address
            Set(.RM, 0b110),
        },
        .mov_acc_mem = &[_]InstFieldInfo{ literal("1010001"), W, DISP_LO, DISP_HI, Set(.D, 0), Set(.REG, 0b000), Set(.MOD, 0b00), Set(.RM, 0b110) },
        .mov_rm_sr = &[_]InstFieldInfo{ literal("100011"), D, literal("0"), MOD, literal("0"), SR, RM, Set(.W, 1) },

        .push_rm = &[_]InstFieldInfo{ literal("11111111"), MOD, literal("110"), RM, Set(.D, 1), Set(.W, 1) },
        .push_reg = &[_]InstFieldInfo{ literal("01010"), REG, Set(.D, 1), Set(.W, 1) },
        .push_seg = &[_]InstFieldInfo{ literal("000"), SR, literal("110"), Set(.D, 1), Set(.W, 1) },

        .pop_rm = &[_]InstFieldInfo{ literal("10001111"), MOD, literal("000"), RM, Set(.D, 1), Set(.W, 1) },
        .pop_reg = &[_]InstFieldInfo{ literal("01011"), REG, Set(.D, 1), Set(.W, 1) },
        .pop_seg = &[_]InstFieldInfo{ literal("000"), SR, literal("111"), Set(.D, 1), Set(.W, 1) },

        .xchg_reg_rm = &[_]InstFieldInfo{ literal("1000011"), W, MOD, REG, RM, Set(.D, 1) },
        .xch_reg_acc = &[_]InstFieldInfo{ literal("10010"), REG, Set(.MOD, 0b11), Set(.RM, 0b00), Set(.W, 1), Set(.D, 0) },

        .in_fixed = &[_]InstFieldInfo{ literal("1110010"), W, DATA_LO, Set(.REG, 0b000), Set(.D, 1) },
        .in_var = &[_]InstFieldInfo{ literal("1110110"), W, Set(.REG, 0b000), Set(.MOD, 0b11), Set(.RM, 0b010), Set(.D, 1), Flag(RM_FORCED_W_REG) },

        .out_fixed = &[_]InstFieldInfo{ literal("1110011"), W, DATA_LO, Set(.REG, 0b000), Set(.D, 0) },
        .out_var = &[_]InstFieldInfo{ literal("1110111"), W, Set(.REG, 0b000), Set(.MOD, 0b11), Set(.RM, 0b010), Set(.D, 0), Flag(RM_FORCED_W_REG) },

        .xlat = &[_]InstFieldInfo{literal("11010111")},
        .lea = &[_]InstFieldInfo{ literal("10001101"), MOD, REG, RM, Set(.D, 1), Set(.W, 1) },
        .lds = &[_]InstFieldInfo{ literal("11000101"), MOD, REG, RM, Set(.D, 1), Set(.W, 1) },
        .les = &[_]InstFieldInfo{ literal("11000100"), MOD, REG, RM, Set(.D, 1), Set(.W, 1) },
        .lahf = &[_]InstFieldInfo{literal("10011111")},
        .sahf = &[_]InstFieldInfo{literal("10011110")},
        .pushf = &[_]InstFieldInfo{literal("10011100")},
        .popf = &[_]InstFieldInfo{literal("10011101")},

        .add_reg_rm = &[_]InstFieldInfo{ literal("000000"), D, W, MOD, REG, RM },
        .add_im_rm = &[_]InstFieldInfo{ literal("100000"), S, W, MOD, literal("000"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .add_im_acc = &[_]InstFieldInfo{ literal("0000010"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .adc_reg_rm = &[_]InstFieldInfo{ literal("000100"), D, W, MOD, REG, RM },
        .adc_im_rm = &[_]InstFieldInfo{ literal("100000"), S, W, MOD, literal("010"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .adc_im_acc = &[_]InstFieldInfo{ literal("0001010"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .inc_rm = &[_]InstFieldInfo{ literal("1111111"), W, MOD, literal("000"), RM, Set(.D, 1) },
        .inc_reg = &[_]InstFieldInfo{ literal("01000"), REG, Set(.D, 1), Set(.W, 1) },
        .aaa = &[_]InstFieldInfo{literal("00110111")},
        .daa = &[_]InstFieldInfo{literal("00100111")},

        .sub_reg_rm = &[_]InstFieldInfo{ literal("001010"), D, W, MOD, REG, RM },
        .sub_im_rm = &[_]InstFieldInfo{ literal("100000"), S, W, MOD, literal("101"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .sub_im_acc = &[_]InstFieldInfo{ literal("0010110"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .sbb_reg_rm = &[_]InstFieldInfo{ literal("000110"), D, W, MOD, REG, RM },
        .sbb_im_rm = &[_]InstFieldInfo{ literal("100000"), S, W, MOD, literal("011"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .sbb_im_acc = &[_]InstFieldInfo{ literal("0001110"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .dec_rm = &[_]InstFieldInfo{ literal("1111111"), W, MOD, literal("001"), RM, Set(.D, 1) },
        .dec_reg = &[_]InstFieldInfo{ literal("01001"), REG, Set(.D, 1), Set(.W, 1) },
        .neg = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("011"), RM, Set(.D, 1) },

        .cmp_rm_reg = &[_]InstFieldInfo{ literal("001110"), D, W, MOD, REG, RM },
        .cmp_im_rm = &[_]InstFieldInfo{ literal("100000"), S, W, MOD, literal("111"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .cmp_im_acc = &[_]InstFieldInfo{ literal("0011110"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },
        .aas = &[_]InstFieldInfo{literal("00111111")},
        .das = &[_]InstFieldInfo{literal("00101111")},
        .mul = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("100"), RM, Set(.D, 1) },
        .imul = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("101"), RM, Set(.D, 1) },
        .aam = &[_]InstFieldInfo{ literal("11010100"), literal("00001010") },
        .div = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("110"), RM, Set(.D, 1) },
        .idiv = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("111"), RM, Set(.D, 1) },
        .aad = &[_]InstFieldInfo{ literal("11010101"), literal("00001010") },
        .cbw = &[_]InstFieldInfo{literal("10011000")},
        .cwd = &[_]InstFieldInfo{literal("10011001")},

        .not = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("010"), RM, Set(.D, 1) },
        .shl = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("100"), RM },
        .shr = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("101"), RM },
        .sar = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("111"), RM },
        .rol = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("000"), RM },
        .ror = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("001"), RM },
        .rcl = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("010"), RM },
        .rcr = &[_]InstFieldInfo{ literal("110100"), V, W, MOD, literal("011"), RM },
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

const std = @import("std");
const assert = @import("utils").assert;
