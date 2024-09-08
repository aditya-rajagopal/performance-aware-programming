pub const rep_test_cases = &[_]rep_test.TestCase{
    rep_test.TestCase{ .name = "Forward Write", .function = write_to_buffer, .config = .{ .mode = .{ .min = 10.0 } } },
    rep_test.TestCase{ .name = "Backward Write", .function = write_to_buffer_backward, .config = .{ .mode = .{ .min = 10.0 } } },
};

pub fn write_to_buffer(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        const buffer = params.allocator.alloc(u8, params.size) catch {
            ctx.report_error("Could not allocate {d} bytes in malloc_rep_test\n", .{params.size});
            continue;
        };
        defer params.allocator.free(buffer);

        ctx.begin();
        for (0..buffer.len) |i| {
            buffer[i] = @truncate(i);
        }
        ctx.end();

        if (buffer.len > 0) {
            ctx.data(buffer.len);
        } else {
            ctx.report_error("Read 0 bytes\n", .{});
        }
    }
}

pub fn write_to_buffer_backward(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        const buffer = params.allocator.alloc(u8, params.size) catch {
            ctx.report_error("Could not allocate {d} bytes in malloc_rep_test\n", .{params.size});
            continue;
        };
        defer params.allocator.free(buffer);

        ctx.begin();
        for (0..buffer.len) |i| {
            buffer[buffer.len - 1 - i] = @truncate(i);
        }
        ctx.end();

        if (buffer.len > 0) {
            ctx.data(buffer.len);
        } else {
            ctx.report_error("Read 0 bytes\n", .{});
        }
    }
}

const UserData = struct {
    size: u64,
    allocator: std.mem.Allocator,
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

    var data: UserData = .{ .size = stat.size, .allocator = gpa_allocator };

    rep_test.initialize();
    rep_test.prepare_all(&data, stat.size);
    try rep_test.run_tests();
}

const std = @import("std");
const perf = @import("perf");
const rep_test = perf.rep_test;
