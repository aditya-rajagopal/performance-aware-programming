pub const rep_test_cases = &[_]rep_test.TestCase{
    rep_test.TestCase{ .name = "Test", .function = rep_test_func, .mode = .{ .min = 10.0 } },
};

pub fn rep_test_func(ctx: *rep_test.Ctx) !void {
    const params: *UserData = @alignCast(@ptrCast(ctx.payload));
    while (ctx.is_running()) {
        const file = std.fs.cwd().openFile(params.file_name, .{}) catch {
            ctx.report_error("File {s} could not be opened\n", .{params.file_name});
            continue;
        };
        defer file.close();

        ctx.begin();
        const bytes_read = try file.readAll(params.buffer);
        ctx.end();

        if (bytes_read > 0) {
            ctx.data(bytes_read);
        } else {
            ctx.report_error("Read 0 bytes for file: {s}\n", .{params.file_name});
        }
    }
}

const UserData = struct {
    buffer: []u8,
    file_name: []const u8,
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

    var data: UserData = .{ .buffer = buffer, .file_name = file_name };

    rep_test.prepare_all(&data, stat.size);
    try rep_test.run_tests();
}

const std = @import("std");
const perf = @import("perf");
const rep_test = perf.rep_test;
