const direction = enum {
    forward,
    backwards,
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

    const page_count_s = args.next() orelse {
        std.log.err("Missing argument [num_pages]\n", .{});
        std.log.err("page_file [num_pages] [?forward/backward]\n", .{});
        return;
    };
    const page_count: u64 = try std.fmt.parseInt(u64, page_count_s, 10);
    const page_size: u64 = 4096;
    const total_size: u64 = page_size * page_size;

    var dir: direction = .forward;
    const dir_s = args.next();
    if (dir_s) |d| {
        if (std.mem.eql(u8, "backward", d)) {
            dir = .backwards;
        } else if (!std.mem.eql(u8, "forward", d)) {
            std.log.err("Incorrect argument [?forward/backward]\n", .{});
            std.log.err("page_file [num_pages] [?forward/backward]\n", .{});
            return;
        }
    }
    const stdout = std.io.getStdOut().writer();

    const handle = tsc.InitializeOSMetrics();
    try stdout.print("{s},{s},{s},{s}\n", .{ "Page Count", "Touch Count", "Fault Count", "Extra Faults" });

    for (0..page_count) |num_touches| {
        const touch_size: u64 = num_touches * page_size;
        const data = windows.kernel32.VirtualAlloc(
            null,
            total_size,
            windows.MEM_RESERVE | windows.MEM_COMMIT,
            windows.PAGE_READWRITE,
        );
        if (data) |d| {
            const array: []u8 = @as([*]u8, @alignCast(@ptrCast(d)))[0..total_size];
            const start_fault_count = tsc.ReadOSPageFaultCount(handle);
            for (0..touch_size) |i| {
                switch (dir) {
                    .forward => array[i] = @truncate(i),
                    .backwards => array[touch_size - i - 1] = @truncate(i),
                }
            }
            const end_fault_count = tsc.ReadOSPageFaultCount(handle);
            const num_faults = end_fault_count - start_fault_count;
            try stdout.print("{d},{d},{d},{d}\n", .{ page_count, num_touches, num_faults, num_faults - num_touches });
            _ = windows.kernel32.VirtualFree(data, 0, windows.MEM_RELEASE);
        } else {
            try stdout.print("ERROR: Unable to allocate memory", .{});
        }
    }
}

const std = @import("std");
const perf = @import("perf");
const rep_test = perf.rep_test;
const tsc = perf.tsc;
const windows = std.os.windows;
