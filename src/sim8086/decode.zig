// const Decode = @This();

pub fn decode_next_instruction(bytecode: []const u8) !Instruction {
    // std.debug.print("Decoding: {d}\n", .{bytecode});
    var instruction: Instruction = Instruction{};
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

        instruction.op_code = op_to_code_map[i];
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
                const bit_mask: u8 = ~(@as(u8, @intCast(0xff)) << @truncate(field.num_bits));

                data = (current_byte >> @truncate(bit_pos)) & bit_mask;
            }

            if (field.inst_type == .LITERAL) {
                if (data != field.payload) {
                    continue :inst_loop;
                }
            } else {
                info[location] = data;
            }

            set[location] = true;
        }
        found = true;
        byte_pos += @intCast(@intFromBool(bit_pos == 0));
        read_pos = byte_pos;
        break;
    }

    assert(found, "Could not find op matching incoming bytecode\n", .{});

    const mod_as_int: usize = @intFromEnum(InstFieldType.MOD);
    const rm_as_int: usize = @intFromEnum(InstFieldType.RM);
    const d_as_int: usize = @intFromEnum(InstFieldType.D);
    const w_as_int: usize = @intFromEnum(InstFieldType.W);
    const reg_as_int: usize = @intFromEnum(InstFieldType.REG);
    const sr_as_int: usize = @intFromEnum(InstFieldType.SR);

    const d = info[d_as_int];
    const w = info[w_as_int];
    const mod = info[mod_as_int];
    const reg = info[reg_as_int];
    const rm = info[rm_as_int];

    instruction.flags |= @truncate(w);

    if (set[sr_as_int]) {
        const sr = info[sr_as_int];
        const es_loc = @as(u32, @intFromEnum(Registers.es));
        instruction.operands[d ^ 1] = Operand{ .register = es_loc + sr };
    }

    if (set[reg_as_int]) {
        instruction.operands[d ^ 1] = Operand{ .register = (w << 3) | reg };
    }

    if (set[mod_as_int]) {
        if (mod == 0b11) {
            instruction.operands[d] = Operand{ .register = (w << 3) | rm };
        } else {
            var disp_bytes_to_read: u8 = 0;

            const direct_addess: bool = mod == 0b00 and rm == 0b110;
            const read_disp_lo: bool = mod == 0b01 or mod == 0b10 or direct_addess;
            const read_disp_hi: bool = mod == 0b10 or direct_addess;

            disp_bytes_to_read += @intCast(@intFromBool(read_disp_lo));
            disp_bytes_to_read += @intCast(@intFromBool(read_disp_hi));

            const disp: i16 = try parse_bytes_as_int(bytecode[read_pos..], disp_bytes_to_read);

            read_pos += disp_bytes_to_read;
            instruction.operands[d] = Operand{
                .memory = .{ .ptr = @truncate(rm), .displacement = disp, .is_direct = direct_addess },
            };
            if (d == 0) {
                instruction.flags |= 0b10;
            }
        }
    }

    if (set[@as(usize, @intFromEnum(InstFieldType.DATA_LO))]) {
        var data_bytes_to_read: usize = 1;
        const data_hi_loc = @as(usize, @intFromEnum(InstFieldType.DATA_LO));
        const read_hi = set[data_hi_loc] and ((info[data_hi_loc] == 0 and w == 1) or (info[data_hi_loc] == 1));

        data_bytes_to_read += @intCast(@intFromBool(read_hi));

        const data: u16 = @bitCast(try parse_bytes_as_int(bytecode[read_pos..], data_bytes_to_read));
        read_pos += data_bytes_to_read;

        instruction.operands[1] = .{ .immediate = data };
    }

    instruction.bytes = @truncate(read_pos);

    return instruction;
}

fn parse_bytes_as_int(bytes: []const u8, num_bytes: usize) !i16 {
    assert(num_bytes <= 2, "Function not designed for more than 2 bytes as of now", .{});
    assert(num_bytes <= bytes.len, "Not enough bytes to read 16bit number: pos {d} remainin {d}", .{ num_bytes, bytes.len });
    switch (num_bytes) {
        0 => return 0,
        1 => {
            const data = std.mem.bytesToValue(i8, bytes[0..num_bytes]);
            return @intCast(data);
        },
        2 => {
            const data = std.mem.bytesToValue(i16, bytes[0..num_bytes]);
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
                .flags = 2,
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
                .flags = 3,
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
                .op_code = .mov,
                .flags = 3,
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
                .flags = 3,
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
                .op_code = .mov,
                .flags = 2,
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
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
                .op_code = .mov,
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

test "decode_next_instruction with add" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b00000001, 0b11011001 },
            .output = Instruction{
                .op_code = .add,
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
                .op_code = .add,
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
                .op_code = .add,
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
                .op_code = .add,
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
                .op_code = .add,
                .flags = 2,
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

test "decode_next_instruction with push" {
    const tests = [_]TestCase{
        .{
            .input = &[_]u8{ 0b11111111, 0b00110001, 0b00000001 },
            .output = Instruction{
                .op_code = .push,
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
                .op_code = .push,
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
                .op_code = .pop,
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
                .op_code = .xchg,
                .flags = 1,
                .bytes = 4,
                .operands = [_]Operand{
                    .{ .register = 0b1001 },
                    .{ .memory = .{ .ptr = 0b001, .displacement = 257, .is_direct = false } },
                },
            },
        },
        .{
            .input = &[_]u8{0b10010111},
            .output = Instruction{
                .op_code = .xchg,
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

fn run_decode_tests(tests: []const TestCase) !void {
    for (tests) |t| {
        const instruction_out = decode_next_instruction(t.input);
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
const assert = @import("utils").assert;
const std = @import("std");
