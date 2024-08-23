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
    comptime assert(op_literal.len <= 8, "Literal string exceeds 8 bits\n", .{});
    const value = std.fmt.parseInt(u8, op_literal, 2) catch unreachable;
    return .{
        .inst_type = .LITERAL,
        .num_bits = op_literal.len,
        .position = 8 - op_literal.len,
        .payload = value,
    };
}

pub const W_FLAG = 0b1;
pub const Z_FLAG = 0b10;
pub const REP_FLAG = 0b100;
pub const REL_JUMP_FLAG = 0b1000;
pub const LOCK_FLAG = 0b10000;
pub const SEGMENT_OVERRIDE_FLAG = 0b100000;
pub const FAR_FLAG = 0b1000000;

const D = InstFieldInfo{ .inst_type = .D, .num_bits = 1 };
const S = InstFieldInfo{ .inst_type = .S, .num_bits = 1 };
const W = InstFieldInfo{ .inst_type = .W, .num_bits = 1 };
const V = InstFieldInfo{ .inst_type = .V, .num_bits = 1 };
const Z = InstFieldInfo{ .inst_type = .Z, .num_bits = 1 };
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
const FORCE_RM_WIDE = InstFieldInfo{ .inst_type = .FLAGS, .num_bits = 0, .payload = W_FLAG };

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
    xchg_reg_acc,
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
    and_reg_rm,
    and_im_rm,
    and_im_acc,
    test_reg_rm,
    test_im_rm,
    test_im_acc,
    or_reg_rm,
    or_im_rm,
    or_im_acc,
    xor_reg_rm,
    xor_im_rm,
    xor_im_acc,
    rep,
    movs,
    cmps,
    scas,
    lods,
    stos,
    call_dir_seg,
    call_ind_seg,
    call_dir_iseg,
    call_ind_iseg,
    jmp_dir_seg,
    jmp_dir_seg_short,
    jmp_ind_seg,
    jmp_dir_iseg,
    jmp_ind_iseg,
    ret_seg,
    ret_seg_sp,
    retf_iseg,
    retf_iseg_sp,
    je,
    jl,
    jle,
    jb,
    jbe,
    jp,
    jo,
    js,
    jne,
    jnl,
    jg,
    jnb,
    ja,
    jnp,
    jno,
    jns,
    loop,
    loopz,
    loopnz,
    jcxz,
    int,
    int3,
    into,
    iret,
    clc,
    cmc,
    stc,
    cld,
    std,
    cli,
    sti,
    hlt,
    wait,
    lock,
    segment,
};

pub const Code = enum {
    unknown,
    mov,
    add,
    adc,
    inc,
    sub,
    sbb,
    dec,
    neg,
    cmp,
};

pub const op_to_code = std.enums.directEnumArrayDefault(Operation, Code, .unknown, 256, .{
    .mov_rm_reg = .mov,
    .mov_im_rm = .mov,
    .mov_im_reg = .mov,
    .mov_mem_acc = .mov,
    .mov_acc_mem = .mov,
    .mov_rm_sr = .mov,
    .add_reg_rm = .add,
    .add_im_rm = .add,
    .add_im_acc = .add,
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
    .adc_reg_rm = .adc,
    .adc_im_rm = .adc,
    .adc_im_acc = .adc,
    .inc_rm = .inc,
    .inc_reg = .inc,
});

pub const op_to_str_map = std.enums.directEnumArrayDefault(Operation, []const u8, null, 256, .{
    .mov_rm_reg = "mov",
    .mov_im_rm = "mov",
    .mov_im_reg = "mov",
    .mov_mem_acc = "mov",
    .mov_acc_mem = "mov",
    .mov_rm_sr = "mov",
    .push_rm = "push",
    .push_reg = "push",
    .push_seg = "push",
    .pop_rm = "pop",
    .pop_reg = "pop",
    .pop_seg = "pop",
    .xchg_reg_rm = "xchg",
    .xchg_reg_acc = "xchg",
    .in_fixed = "in",
    .in_var = "in",
    .out_fixed = "out",
    .out_var = "out",
    .xlat = "xlat",
    .lea = "lea",
    .lds = "lds",
    .les = "les",
    .lahf = "lahf",
    .sahf = "sahf",
    .pushf = "pushf",
    .popf = "popf",
    .add_reg_rm = "add",
    .add_im_rm = "add",
    .add_im_acc = "add",
    .adc_reg_rm = "adc",
    .adc_im_rm = "adc",
    .adc_im_acc = "adc",
    .inc_rm = "inc",
    .inc_reg = "inc",
    .aaa = "aaa",
    .daa = "daa",
    .sub_reg_rm = "sub",
    .sub_im_rm = "sub",
    .sub_im_acc = "sub",
    .sbb_reg_rm = "sbb",
    .sbb_im_rm = "sbb",
    .sbb_im_acc = "sbb",
    .dec_rm = "dec",
    .dec_reg = "dec",
    .neg = "neg",
    .cmp_rm_reg = "cmp",
    .cmp_im_rm = "cmp",
    .cmp_im_acc = "cmp",
    .aas = "aas",
    .das = "das",
    .mul = "mul",
    .imul = "imul",
    .aam = "aam",
    .div = "div",
    .idiv = "idiv",
    .aad = "aad",
    .cbw = "cbw",
    .cwd = "cwd",
    .not = "not",
    .shl = "shl",
    // .sal ="sal",
    .shr = "shr",
    .sar = "sar",
    .rol = "rol",
    .ror = "ror",
    .rcl = "rcl",
    .rcr = "rcr",
    .and_reg_rm = "and",
    .and_im_rm = "and",
    .and_im_acc = "and",
    .test_reg_rm = "test",
    .test_im_rm = "test",
    .test_im_acc = "test",
    .or_reg_rm = "or",
    .or_im_rm = "or",
    .or_im_acc = "or",
    .xor_reg_rm = "xor",
    .xor_im_rm = "xor",
    .xor_im_acc = "xor",
    .rep = "rep",
    .movs = "movs",
    .cmps = "cmps",
    .scas = "scas",
    .lods = "lods",
    .stos = "stos",
    .call_dir_seg = "call",
    .call_ind_seg = "call",
    .call_dir_iseg = "call",
    .call_ind_iseg = "call",
    .jmp_dir_seg = "jmp",
    .jmp_dir_seg_short = "jmp",
    .jmp_ind_seg = "jmp",
    .jmp_dir_iseg = "jmp",
    .jmp_ind_iseg = "jmp",
    .ret_seg = "ret",
    .ret_seg_sp = "ret",
    .retf_iseg = "retf",
    .retf_iseg_sp = "retf",
    .je = "je",
    .jl = "jl",
    .jle = "jle",
    .jb = "jb",
    .jbe = "jbe",
    .jp = "jp",
    .jo = "jo",
    .js = "js",
    .jne = "jne",
    .jnl = "jnl",
    .jg = "jg",
    .jnb = "jnb",
    .ja = "ja",
    .jnp = "jnp",
    .jno = "jno",
    .jns = "jns",
    .loop = "loop",
    .loopz = "loopz",
    .loopnz = "loopnz",
    .jcxz = "jcxz",
    .int = "int",
    .int3 = "int3",
    .into = "into",
    .iret = "iret",
    .clc = "clc",
    .cmc = "cmc",
    .stc = "stc",
    .cld = "cld",
    .std = "std",
    .cli = "cli",
    .sti = "sti",
    .hlt = "hlt",
    .wait = "wait",
    .lock = "lock",
    .segment = "segment",
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

        .xchg_reg_rm = &[_]InstFieldInfo{ literal("1000011"), W, MOD, REG, RM, Set(.D, 0) },
        .xchg_reg_acc = &[_]InstFieldInfo{ literal("10010"), REG, Set(.MOD, 0b11), Set(.RM, 0b00), Set(.W, 1), Set(.D, 0) },

        .in_fixed = &[_]InstFieldInfo{ literal("1110010"), W, DATA_LO, Set(.REG, 0b000), Set(.D, 1) },
        .in_var = &[_]InstFieldInfo{ literal("1110110"), W, Set(.REG, 0b000), Set(.MOD, 0b11), Set(.RM, 0b010), Set(.D, 1), Flag(W_FLAG) },

        .out_fixed = &[_]InstFieldInfo{ literal("1110011"), W, DATA_LO, Set(.REG, 0b000), Set(.D, 0) },
        .out_var = &[_]InstFieldInfo{ literal("1110111"), W, Set(.REG, 0b000), Set(.MOD, 0b11), Set(.RM, 0b010), Set(.D, 0), Flag(W_FLAG) },

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

        .and_reg_rm = &[_]InstFieldInfo{ literal("001000"), D, W, MOD, REG, RM },
        .and_im_rm = &[_]InstFieldInfo{ literal("1000000"), W, MOD, literal("100"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .and_im_acc = &[_]InstFieldInfo{ literal("0010010"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .test_reg_rm = &[_]InstFieldInfo{ literal("1000010"), W, MOD, REG, RM },
        .test_im_rm = &[_]InstFieldInfo{ literal("1111011"), W, MOD, literal("000"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .test_im_acc = &[_]InstFieldInfo{ literal("1010100"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .or_reg_rm = &[_]InstFieldInfo{ literal("000010"), D, W, MOD, REG, RM },
        .or_im_rm = &[_]InstFieldInfo{ literal("1000000"), W, MOD, literal("001"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .or_im_acc = &[_]InstFieldInfo{ literal("0000110"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .xor_reg_rm = &[_]InstFieldInfo{ literal("001100"), D, W, MOD, REG, RM },
        .xor_im_rm = &[_]InstFieldInfo{ literal("1000000"), W, MOD, literal("110"), RM, DATA_LO, DATA_HI_OPT, Set(.D, 0) },
        .xor_im_acc = &[_]InstFieldInfo{ literal("0011010"), W, DATA_LO, DATA_HI_OPT, Set(.D, 1), Set(.REG, 0b000) },

        .rep = &[_]InstFieldInfo{ literal("1111001"), Z },
        .movs = &[_]InstFieldInfo{ literal("1010010"), W },
        .cmps = &[_]InstFieldInfo{ literal("1010011"), W },
        .scas = &[_]InstFieldInfo{ literal("1010111"), W },
        .lods = &[_]InstFieldInfo{ literal("1010110"), W },
        .stos = &[_]InstFieldInfo{ literal("1010101"), W },

        .call_dir_seg = &[_]InstFieldInfo{ literal("11101000"), DISP_LO, DISP_HI, Flag(REL_JUMP_FLAG) },
        .call_ind_seg = &[_]InstFieldInfo{ literal("11111111"), MOD, literal("010"), RM, Set(.W, 1) },
        .call_dir_iseg = &[_]InstFieldInfo{ literal("10011010"), DISP_LO, DISP_HI, DATA_LO, DATA_HI, Set(.W, 1), Flag(FAR_FLAG) },
        .call_ind_iseg = &[_]InstFieldInfo{ literal("11111111"), MOD, literal("011"), RM, Set(.W, 1), Flag(FAR_FLAG) },

        .jmp_dir_seg = &[_]InstFieldInfo{ literal("11101001"), DISP_LO, DISP_HI, Flag(REL_JUMP_FLAG) },
        .jmp_dir_seg_short = &[_]InstFieldInfo{ literal("11101011"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jmp_ind_seg = &[_]InstFieldInfo{ literal("11111111"), MOD, literal("100"), RM, Set(.W, 1) },
        .jmp_dir_iseg = &[_]InstFieldInfo{ literal("11101010"), DISP_LO, DISP_HI, DATA_LO, DATA_HI, Set(.W, 1), Flag(FAR_FLAG) },
        .jmp_ind_iseg = &[_]InstFieldInfo{ literal("11111111"), MOD, literal("101"), RM, Set(.W, 1), Flag(FAR_FLAG) },

        .ret_seg = &[_]InstFieldInfo{literal("11000011")},
        .ret_seg_sp = &[_]InstFieldInfo{ literal("11000010"), DATA_LO, DATA_HI },
        .retf_iseg = &[_]InstFieldInfo{ literal("11001011"), Flag(FAR_FLAG) },
        .retf_iseg_sp = &[_]InstFieldInfo{ literal("11001010"), DATA_LO, DATA_HI, Flag(FAR_FLAG) },

        .je = &[_]InstFieldInfo{ literal("01110100"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jl = &[_]InstFieldInfo{ literal("01111100"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jle = &[_]InstFieldInfo{ literal("01111110"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jb = &[_]InstFieldInfo{ literal("01110010"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jbe = &[_]InstFieldInfo{ literal("01110110"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jp = &[_]InstFieldInfo{ literal("01111010"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jo = &[_]InstFieldInfo{ literal("01110000"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .js = &[_]InstFieldInfo{ literal("01111000"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jne = &[_]InstFieldInfo{ literal("01110101"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jnl = &[_]InstFieldInfo{ literal("01111101"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jg = &[_]InstFieldInfo{ literal("01111111"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jnb = &[_]InstFieldInfo{ literal("01110011"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .ja = &[_]InstFieldInfo{ literal("01110111"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jnp = &[_]InstFieldInfo{ literal("01111011"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jno = &[_]InstFieldInfo{ literal("01110001"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jns = &[_]InstFieldInfo{ literal("01111001"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .loop = &[_]InstFieldInfo{ literal("11100010"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .loopz = &[_]InstFieldInfo{ literal("11100001"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .loopnz = &[_]InstFieldInfo{ literal("11100000"), DISP_LO, Flag(REL_JUMP_FLAG) },
        .jcxz = &[_]InstFieldInfo{ literal("11100011"), DISP_LO, Flag(REL_JUMP_FLAG) },

        .int = &[_]InstFieldInfo{ literal("11001101"), DATA_LO },
        .int3 = &[_]InstFieldInfo{literal("11001100")},
        .into = &[_]InstFieldInfo{literal("11001110")},
        .iret = &[_]InstFieldInfo{literal("11001111")},

        .clc = &[_]InstFieldInfo{literal("11111000")},
        .cmc = &[_]InstFieldInfo{literal("11110101")},
        .stc = &[_]InstFieldInfo{literal("11111001")},
        .cld = &[_]InstFieldInfo{literal("11111100")},
        .std = &[_]InstFieldInfo{literal("11111101")},
        .cli = &[_]InstFieldInfo{literal("11111010")},
        .sti = &[_]InstFieldInfo{literal("11111011")},
        .hlt = &[_]InstFieldInfo{literal("11110100")},
        .wait = &[_]InstFieldInfo{literal("10011011")},

        .lock = &[_]InstFieldInfo{literal("11110000")},
        .segment = &[_]InstFieldInfo{ literal("001"), SR, literal("110") },
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
    explicit_segment: struct { displacement: i16, segment: u16 },
    none: void,
};

pub const Instruction = struct {
    op_code: Operation,
    flags: u8 = 0, // 0000 000W
    bytes: u8 = 0, // number of bytes to read for this op
    segment_override: u8 = 0,
    operands: [2]Operand = [_]Operand{ .none, .none }, // the first and second operand that this op works on.
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

const std = @import("std");
const assert = @import("utils").assert;
