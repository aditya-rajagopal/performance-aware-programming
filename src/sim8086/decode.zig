const mod_as_int: usize = @intFromEnum(InstFieldType.MOD);
const rm_as_int: usize = @intFromEnum(InstFieldType.RM);
const d_as_int: usize = @intFromEnum(InstFieldType.D);
const w_as_int: usize = @intFromEnum(InstFieldType.W);
const reg_as_int: usize = @intFromEnum(InstFieldType.REG);
const sr_as_int: usize = @intFromEnum(InstFieldType.SR);
const flag_as_int: usize = @intFromEnum(InstFieldType.FLAGS);
const s_as_int: usize = @intFromEnum(InstFieldType.S);
const v_as_int: usize = @intFromEnum(InstFieldType.V);
const z_as_int: usize = @intFromEnum(InstFieldType.Z);
const disp_lo_loc: usize = @intFromEnum(InstFieldType.DISP_LO);
const disp_hi_loc = @as(usize, @intFromEnum(InstFieldType.DISP_HI));
const data_lo_loc: usize = @intFromEnum(InstFieldType.DATA_LO);
const data_hi_loc = @as(usize, @intFromEnum(InstFieldType.DATA_HI));

pub fn decode_next_instruction(bytecode: []const u8, flags: u8, segment_override: u32) !Instruction {
    var instruction: Instruction = Instruction{
        .op_code = .mov_rm_reg,
        .flags = flags,
        .segment_override = @truncate(segment_override),
    };
    var info = std.enums.directEnumArrayDefault(InstFieldType, u32, 0, 0, .{});
    var set = std.enums.directEnumArrayDefault(InstFieldType, bool, false, 0, .{});

    var found: bool = false;
    var inst_fields: []const InstFieldInfo = undefined;

    // The op code will be in the first byte
    const op_byte = bytecode[0];
    var read_pos: usize = 0;

    // TODO: Test if inlining this for loop makes it faster or if the compiler inlines it for us
    inst_loop: for (instruction_map, 0..) |inst, i| {
        const op_found = op_byte >> @intCast(inst[0].position) == inst[0].payload;

        if (!op_found) {
            continue;
        }
        // std.debug.print("Testing op: {s}\n", .{@tagName(op_to_code_map[i])});

        instruction.op_code = @enumFromInt(i);
        inst_fields = inst;
        info[@as(usize, @intFromEnum(InstFieldType.LITERAL))] = @intCast(i);
        set[@as(usize, @intFromEnum(InstFieldType.LITERAL))] = true;
        // break;

        var bit_pos: usize = 8 - inst_fields[0].num_bits;
        var byte_pos: usize = 0;
        var current_byte = op_byte;

        for (inst_fields[1..]) |field| {
            const location: usize = @intFromEnum(field.inst_type);

            var data = field.payload;
            if (field.num_bits > 0) {
                if (bit_pos == 0) {
                    byte_pos += 1;
                    current_byte = bytecode[byte_pos];
                    bit_pos = 8;
                }

                assert(
                    field.num_bits <= bit_pos,
                    "Requesting to check more bits than is remaining: {d} only have {d}\n",
                    .{ field.num_bits, bit_pos },
                );

                bit_pos -|= field.num_bits;
                const bit_mask: u8 = @truncate(~(@as(u16, @intCast(0xff)) << @truncate(field.num_bits)));
                data = (current_byte >> @truncate(bit_pos)) & bit_mask;
            }

            if (field.inst_type == .LITERAL) {
                if (data != field.payload) {
                    continue :inst_loop;
                }
            } else {
                info[location] |= data;
            }

            set[location] = true;
        }
        found = true;
        byte_pos += @intCast(@intFromBool(bit_pos == 0));
        read_pos = byte_pos;
        break;
    }

    assert(found, "Could not find op matching incoming bytecode\n", .{});

    const d = info[d_as_int];
    const w = info[w_as_int];
    const s = info[s_as_int];
    const v = info[v_as_int];
    const z = info[z_as_int];

    const mod = info[mod_as_int];
    const reg = info[reg_as_int];
    const rm = info[rm_as_int];

    instruction.flags |= @truncate(w);

    if (z == 1) {
        std.debug.print("Setting Z flag\n", .{});
        instruction.flags |= @truncate(Z_FLAG);
    }

    if (set[sr_as_int]) {
        const sr = info[sr_as_int];
        const es_loc = @as(u32, @intFromEnum(Registers.es));
        instruction.operands[d ^ 1] = Operand{ .register = es_loc + sr };
    }

    if (set[reg_as_int]) {
        instruction.operands[d ^ 1] = Operand{ .register = (w << 3) | reg };
    }

    const is_rel_jump: u8 = @as(u8, @truncate(info[flag_as_int])) & REL_JUMP_FLAG;
    instruction.flags |= is_rel_jump;

    const is_far_jump: u8 = @as(u8, @truncate(info[flag_as_int])) & FAR_FLAG;
    instruction.flags |= is_far_jump;

    // check if you need to write something
    var disp_bytes_to_read: u8 = 0;

    const direct_addess: bool = mod == 0b00 and rm == 0b110;
    const read_disp_lo: bool = mod == 0b01 or mod == 0b10 or direct_addess or set[disp_lo_loc];
    const read_disp_hi: bool = mod == 0b10 or direct_addess or set[disp_hi_loc];

    disp_bytes_to_read += @intCast(@intFromBool(read_disp_lo));
    disp_bytes_to_read += @intCast(@intFromBool(read_disp_hi));

    var data_bytes_to_read: usize = @intFromBool(set[data_lo_loc]);

    const read_hi = set[data_hi_loc] and ((info[data_hi_loc] == 0 and w == 1 and s != 1) or (info[data_hi_loc] == 1));

    data_bytes_to_read += @intCast(@intFromBool(read_hi));

    const disp: i16 = @bitCast(try parse_bytes_as_int(bytecode[read_pos..], disp_bytes_to_read, !read_disp_hi));
    read_pos += disp_bytes_to_read;
    const data: u16 = try parse_bytes_as_int(bytecode[read_pos..], data_bytes_to_read, s == 1);
    read_pos += data_bytes_to_read;

    if (set[mod_as_int]) {
        if (mod == 0b11) {
            const rm_forced_wide: u32 = @intFromBool(set[flag_as_int] and (info[flag_as_int] & W_FLAG == 1));
            instruction.operands[d] = Operand{ .register = ((w | rm_forced_wide) << 3) | rm };
        } else {
            instruction.operands[d] = Operand{
                .memory = .{ .ptr = @truncate(rm), .displacement = disp, .is_direct = direct_addess },
            };
        }
    }

    // normally put the immediate value in position 1. But sometimes pos 0 might be empty. If that is
    // the case then put it in position 0.
    var position: usize = 1;
    if (instruction.operands[0] == .none) {
        position = 0;
    }

    if (set[data_lo_loc] and set[disp_lo_loc] and !set[mod_as_int]) {
        instruction.operands[position] = .{
            .explicit_segment = .{ .displacement = disp, .segment = data },
        };
    } else if (set[data_lo_loc]) {
        instruction.operands[position] = .{ .immediate = data };
    } else if (set[disp_lo_loc] and is_rel_jump != 0) {
        instruction.operands[position] = .{ .immediate = @bitCast(disp) };
    } else if (set[v_as_int]) {
        if (v == 1) {
            instruction.operands[position] = .{ .register = 0b0001 };
        } else {
            instruction.operands[position] = .{ .immediate = 1 };
        }
    }

    if (instruction.op_code == .rep) {
        instruction.flags |= @truncate(REP_FLAG);
        instruction = try decode_next_instruction(bytecode[read_pos..], instruction.flags, 0);
    } else if (instruction.op_code == .lock) {
        instruction.flags |= @truncate(LOCK_FLAG);
        instruction = try decode_next_instruction(bytecode[read_pos..], instruction.flags, 0);
    } else if (instruction.op_code == .segment) {
        instruction.flags |= @truncate(SEGMENT_OVERRIDE_FLAG);
        instruction = try decode_next_instruction(bytecode[read_pos..], instruction.flags, instruction.operands[1].register);
    }

    instruction.bytes += @truncate(read_pos);

    return instruction;
}

fn parse_bytes_as_int(bytes: []const u8, num_bytes: usize, sign_extend: bool) !u16 {
    assert(num_bytes <= 2, "Function not designed for more than 2 bytes as of now", .{});
    assert(num_bytes <= bytes.len, "Not enough bytes to read 16bit number: pos {d} remainin {d}", .{ num_bytes, bytes.len });
    switch (num_bytes) {
        0 => return 0,
        1 => {
            if (sign_extend) {
                const data = @as(i16, @intCast(std.mem.bytesToValue(i8, bytes[0..num_bytes])));
                return @bitCast(data);
            } else {
                const data = @as(u16, @intCast(std.mem.bytesToValue(u8, bytes[0..num_bytes])));
                return @intCast(data);
            }
        },
        2 => {
            const data = std.mem.bytesToValue(u16, bytes[0..num_bytes]);
            return data;
        },
        else => unreachable,
    }
}

const TestCase = struct {
    input: []const u8,
    output: Instruction,
};

test "decode_next_instruction with mov_reg_rm" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10001001, 0b11011001 },
            .output = Instruction{
                .op_code = .mov_rm_reg,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b1001 },
                    .{ .register = 0b1011 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001010, 0b00000000 },
            .output = Instruction{
                .op_code = .mov_rm_reg,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .memory = .{ .ptr = 0b00, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001011, 0b01010110, 0b00000000 },
            .output = Instruction{
                .op_code = .mov_rm_reg,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001011, 0b00010110, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_rm_reg,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001000, 0b10000000, 0b10000111, 0b00010011 },
            .output = Instruction{
                .op_code = .mov_rm_reg,
                .flags = 0,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b000, .displacement = 4999, .is_direct = false } },
                    .{ .register = 0b0000 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with mov_im_reg" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10111001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_im_reg,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1001 },
                    .{ .immediate = 257 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10110001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_im_reg,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0001 },
                    .{ .immediate = 1 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with mov_im_rm" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11000111, 0b00000001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_im_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b001, .displacement = 0, .is_direct = false } },
                    .{ .immediate = 257 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000111, 0b10000001, 0b00000001, 0b00000001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_im_rm,
                .flags = 1,
                .bytes = 6,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b001, .displacement = 257, .is_direct = false } },
                    .{ .immediate = 257 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with mov_memacc" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10100001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_mem_acc,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10100000, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_mem_acc,
                .flags = 0,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with mov_acc_mem" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10100011, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_acc_mem,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                    .{ .register = 0b1000 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10100010, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_acc_mem,
                .flags = 0,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                    .{ .register = 0b0000 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with mov_rm_sr" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10001110, 0b11000000 },
            .output = Instruction{
                .op_code = .mov_rm_sr,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b10000 },
                    .{ .register = 0b1000 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001100, 0b11000000 },
            .output = Instruction{
                .op_code = .mov_rm_sr,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .register = 0b10000 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001110, 0b01000000, 0b00000000, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_rm_sr,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b10000 },
                    .{ .memory = .{ .ptr = 0b000, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001110, 0b10011001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .mov_rm_sr,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b10011 },
                    .{ .memory = .{ .ptr = 0b001, .displacement = 257, .is_direct = false } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with push" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11111111, 0b00110001, 0b00000001 },
            .output = Instruction{
                .op_code = .push_rm,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .none,
                    .{ .memory = .{ .ptr = 0b001, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11111111, 0b11110000, 0b00000001 },
            .output = Instruction{
                .op_code = .push_rm,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .none,
                    .{ .register = 0b1000 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with pop" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10001111, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .pop_rm,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .none,
                    .{ .memory = .{ .ptr = 0b001, .displacement = 0, .is_direct = false } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with xchg" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10000111, 0b10001001, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .xchg_reg_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b001, .displacement = 257, .is_direct = false } },
                    .{ .register = 0b1001 },
                },
            },
        },
        .{
            .input = &[_]u8{0b10010111},
            .output = Instruction{
                .op_code = .xchg_reg_acc,
                .flags = 1,
                .bytes = 1,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .register = 0b1111 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with in" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11100100, 0b11001000 },
            .output = Instruction{
                .op_code = .in_fixed,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .immediate = 0b11001000 },
                },
            },
        },
        .{
            .input = &[_]u8{0b11101100},
            .output = Instruction{
                .op_code = .in_var,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .register = 0b1010 },
                },
            },
        },
        .{
            .input = &[_]u8{0b11101101},
            .output = Instruction{
                .op_code = .in_var,
                .flags = 1,
                .bytes = 1,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .register = 0b1010 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with out" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11100111, 0b00101100 },
            .output = Instruction{
                .op_code = .out_fixed,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .immediate = 0b00101100 },
                    .{ .register = 0b1000 },
                },
            },
        },
        .{
            .input = &[_]u8{0b11101110},
            .output = Instruction{
                .op_code = .out_var,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .register = 0b0000 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with xlat" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{0b11010111},
            .output = Instruction{
                .op_code = .xlat,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{
                    .none,
                    .none,
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with lea" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b10001101, 0b10000001, 0b10001100, 0b00000101 },
            .output = Instruction{
                .op_code = .lea,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .memory = .{ .ptr = 0b001, .displacement = 1420, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001101, 0b01011110, 0b11001110 },
            .output = Instruction{
                .op_code = .lea,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1011 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = -50, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001101, 0b10100110, 0b00010101, 0b11111100 },
            .output = Instruction{
                .op_code = .lea,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1100 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = -1003, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10001101, 0b01111000, 0b11111001 },
            .output = Instruction{
                .op_code = .lea,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1111 },
                    .{ .memory = .{ .ptr = 0b000, .displacement = -7, .is_direct = false } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with lds" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11000101, 0b10000001, 0b10001100, 0b00000101 },
            .output = Instruction{
                .op_code = .lds,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .memory = .{ .ptr = 0b001, .displacement = 1420, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000101, 0b01011110, 0b11001110 },
            .output = Instruction{
                .op_code = .lds,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1011 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = -50, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000101, 0b10100110, 0b00010101, 0b11111100 },
            .output = Instruction{
                .op_code = .lds,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1100 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = -1003, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000101, 0b01111000, 0b11111001 },
            .output = Instruction{
                .op_code = .lds,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1111 },
                    .{ .memory = .{ .ptr = 0b000, .displacement = -7, .is_direct = false } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with les" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11000100, 0b10000001, 0b10001100, 0b00000101 },
            .output = Instruction{
                .op_code = .les,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1000 },
                    .{ .memory = .{ .ptr = 0b001, .displacement = 1420, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000100, 0b01011110, 0b11001110 },
            .output = Instruction{
                .op_code = .les,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1011 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = -50, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000100, 0b10100110, 0b00010101, 0b11111100 },
            .output = Instruction{
                .op_code = .les,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1100 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = -1003, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11000100, 0b01111000, 0b11111001 },
            .output = Instruction{
                .op_code = .les,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1111 },
                    .{ .memory = .{ .ptr = 0b000, .displacement = -7, .is_direct = false } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with lahf, sahf, pushf, popf" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{0b10011111},
            .output = Instruction{
                .op_code = .lahf,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{ .none, .none },
            },
        },
        .{
            .input = &[_]u8{0b10011110},
            .output = Instruction{
                .op_code = .sahf,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{ .none, .none },
            },
        },
        .{
            .input = &[_]u8{0b10011100},
            .output = Instruction{
                .op_code = .pushf,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{ .none, .none },
            },
        },
        .{
            .input = &[_]u8{0b10011101},
            .output = Instruction{
                .op_code = .popf,
                .flags = 0,
                .bytes = 1,
                .operands = [_]Operand{ .none, .none },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with add" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b00000001, 0b11011001 },
            .output = Instruction{
                .op_code = .add_reg_rm,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b1001 },
                    .{ .register = 0b1011 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00000010, 0b00000000 },
            .output = Instruction{
                .op_code = .add_reg_rm,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .memory = .{ .ptr = 0b00, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00000011, 0b01010110, 0b00000000 },
            .output = Instruction{
                .op_code = .add_reg_rm,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00000011, 0b00010110, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .add_reg_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00000000, 0b10000000, 0b10000111, 0b00010011 },
            .output = Instruction{
                .op_code = .add_reg_rm,
                .flags = 0,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b000, .displacement = 4999, .is_direct = false } },
                    .{ .register = 0b0000 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10000001, 0b011000100, 0b10001000, 0b00000001 },
            .output = Instruction{
                .op_code = .add_im_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1100 },
                    .{ .immediate = 392 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00000100, 0b00001001 },
            .output = Instruction{
                .op_code = .add_im_acc,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .immediate = 9 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with adc" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b00010001, 0b11011001 },
            .output = Instruction{
                .op_code = .adc_reg_rm,
                .flags = 1,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b1001 },
                    .{ .register = 0b1011 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00010010, 0b00000000 },
            .output = Instruction{
                .op_code = .adc_reg_rm,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .memory = .{ .ptr = 0b00, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00010011, 0b01010110, 0b00000000 },
            .output = Instruction{
                .op_code = .adc_reg_rm,
                .flags = 1,
                .bytes = 3,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 0, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00010011, 0b00010110, 0b00000001, 0b00000001 },
            .output = Instruction{
                .op_code = .adc_reg_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1010 },
                    .{ .memory = .{ .ptr = 0b110, .displacement = 257, .is_direct = true } },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00010000, 0b10000000, 0b10000111, 0b00010011 },
            .output = Instruction{
                .op_code = .adc_reg_rm,
                .flags = 0,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .memory = .{ .ptr = 0b000, .displacement = 4999, .is_direct = false } },
                    .{ .register = 0b0000 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b10000001, 0b011010100, 0b10001000, 0b00000001 },
            .output = Instruction{
                .op_code = .adc_im_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1100 },
                    .{ .immediate = 392 },
                },
            },
        },
        .{
            .input = &[_]u8{ 0b00010100, 0b00001001 },
            .output = Instruction{
                .op_code = .adc_im_acc,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .{ .register = 0b0000 },
                    .{ .immediate = 9 },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with inc" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{0b01000001},
            .output = Instruction{
                .op_code = .inc_reg,
                .flags = 1,
                .bytes = 1,
                .operands = [_]Operand{
                    .{ .register = 0b1001 },
                    .none,
                },
            },
        },
        .{
            .input = &[_]u8{ 0b11111111, 0b10000011, 0b11000100, 0b11011000 },
            .output = Instruction{
                .op_code = .inc_rm,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .none,
                    .{ .memory = .{ .ptr = 0b011, .displacement = -10044, .is_direct = false } },
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

test "decode_next_instruction with aam" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11010100, 0b00001010 },
            .output = Instruction{
                .op_code = .aam,
                .flags = 0,
                .bytes = 2,
                .operands = [_]Operand{
                    .none,
                    .none,
                },
            },
        },
    };

    try run_decode_tests(&tests);
}

fn run_decode_tests(tests: []const TestCase) !void {
    for (tests) |t| {
        const instruction_out = decode_next_instruction(t.input, 0, 0);
        try std.testing.expectEqualDeep(t.output, instruction_out);
    }
}

const tables = @import("tables.zig");
const Code = tables.Code;
const instruction_map = tables.instruction_map;
const op_to_code_map = tables.op_to_code_map;
const InstFieldType = tables.InstFieldType;
const InstFieldInfo = tables.InstFieldInfo;
const Instruction = tables.Instruction;
const Registers = tables.Registers;
const Operand = tables.Operand;
const W_FLAG = tables.W_FLAG;
const Z_FLAG = tables.Z_FLAG;
const REP_FLAG = tables.REP_FLAG;
const REL_JUMP_FLAG = tables.REL_JUMP_FLAG;
const LOCK_FLAG = tables.LOCK_FLAG;
const SEGMENT_OVERRIDE_FLAG = tables.SEGMENT_OVERRIDE_FLAG;
const FAR_FLAG = tables.FAR_FLAG;
const assert = @import("utils").assert;
const std = @import("std");
