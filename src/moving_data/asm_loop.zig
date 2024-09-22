pub const rep_test_cases = &[_]rep_test.TestCase{
    rep_test.TestCase{ .name = "DECLoopASM", .function = write_to_buffer_dec, .config = .{ .mode = .{ .min = 5.0 } } },
    rep_test.TestCase{ .name = "WriteAllBytes", .function = write_to_buffer, .config = .{ .mode = .{ .min = 5.0 } } },
    rep_test.TestCase{ .name = "NormalLoopASM", .function = write_to_buffer_asm, .config = .{ .mode = .{ .min = 5.0 } } },
    rep_test.TestCase{ .name = "NOPLoopASM", .function = write_to_buffer_nop, .config = .{ .mode = .{ .min = 5.0 } } },
    rep_test.TestCase{ .name = "CMPLoopASM", .function = write_to_buffer_cmp, .config = .{ .mode = .{ .min = 5.0 } } },
};

extern fn NormalLoopASM(len: u64, data: [*]u8) void;
extern fn NOPLoopASM(len: u64) void;
extern fn CMPLoopASM(len: u64) void;
extern fn DECLoopASM(len: u64) void;

pub fn write_to_buffer(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        ctx.begin();
        for (0..params.buffer.len) |i| {
            params.buffer[i] = @truncate(i);
        }
        ctx.end();
        ctx.data(params.buffer.len);
    }
}

pub fn write_to_buffer_asm(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        ctx.begin();
        NormalLoopASM(params.buffer.len, params.buffer.ptr);
        ctx.end();
        ctx.data(params.buffer.len);
    }
}

pub fn write_to_buffer_nop(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        ctx.begin();
        NOPLoopASM(params.buffer.len);
        ctx.end();
        ctx.data(params.buffer.len);
    }
}

pub fn write_to_buffer_cmp(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        ctx.begin();
        CMPLoopASM(params.buffer.len);
        ctx.end();
        ctx.data(params.buffer.len);
    }
}

pub fn write_to_buffer_dec(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        ctx.begin();
        DECLoopASM(params.buffer.len);
        ctx.end();
        ctx.data(params.buffer.len);
    }
}

const UserData = struct {
    size: u64,
    buffer: []u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var args = try std.process.argsWithAllocator(gpa_allocator);
    defer args.deinit();
    _ = args.next().?;

    const file_name = args.next() orelse {
        std.log.err("Missing argument [file]", .{});
        std.log.err("f_test [file]\n", .{});
        return;
    };

    const file = try std.fs.cwd().openFile(file_name, .{});
    const stat = try file.stat();
    file.close();
    const buffer = try gpa_allocator.alloc(u8, stat.size);
    defer gpa_allocator.free(buffer);

    var data: UserData = .{ .size = stat.size, .buffer = buffer };

    rep_test.initialize();
    rep_test.prepare_all(&data, stat.size);
    try rep_test.run_tests();
}

const std = @import("std");
const perf = @import("perf");
const rep_test = perf.rep_test;
