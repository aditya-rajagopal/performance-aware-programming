pub const tsc = @import("tsc.zig");

//TODO: Can i at comptime create an array here based on how many times tracer is called?

const Tracer = @This();

tracer_info: std.MultiArrayList(TracerInfo),
// tracer_marks: std.MultiArrayList(Mark),
allocator: Allocator,

const TracerInfo = struct {
    // line: u32,
    // file_name: []const u8,
    fn_name: []const u8,
    name: ?[]const u8,
    start_time: u64,
    end_time: u64,
    hit_count: usize = 0,
};

const Mark = struct {
    pos: usize,
    time: u64,
};

pub const MarkHandle = usize;

var tracer: Tracer = undefined;
var is_initialized: bool = false;
var cpu_frequency: f64 = 0;

const root_node: usize = 0;

pub fn tracer_initialize(allocator: Allocator, comptime name: []const u8, capacity: usize, calibrate_time_ms: u64) !void {
    if (is_initialized) {
        std.log.err("Trying to reinitialize Tracer\n", .{});
        return;
    }
    tracer = Tracer{
        .allocator = allocator,
        .tracer_info = .{},
        // .tracer_marks = .{},
    };
    try tracer.tracer_info.ensureTotalCapacity(allocator, capacity);
    cpu_frequency = tsc.calibrate_frequency(calibrate_time_ms);
    is_initialized = true;
    _ = trace(@src().fn_name, name);
}

pub fn tracer_finish() void {
    tracer.tracer_info.items(.end_time)[root_node] = tsc.rdtsc();
}

pub fn tracer_shutdown() void {
    if (!is_initialized) {
        std.log.err("Trying to shutdown non initialzied tracer\n", .{});
        return;
    }
    tracer.tracer_info.deinit(tracer.allocator);
}

// pub fn trace(comptime src: std.builtin.SourceLocation, comptime name: ?[]const u8) MarkHandle {
pub fn trace(comptime fn_name: []const u8, comptime name: ?[]const u8) MarkHandle {
    if (!is_initialized) {
        return 0;
    }
    const pos = tracer.tracer_info.len;
    tracer.tracer_info.appendAssumeCapacity(TracerInfo{
        // .file_name = src.file,
        .fn_name = fn_name,
        .name = name,
        // .line = src.line,
        .start_time = tsc.rdtsc(),
        .end_time = 0,
    });
    return pos;
}

pub fn trace_end(position: usize) void {
    if (!is_initialized) {
        return;
    }
    tracer.tracer_info.items(.end_time)[position] = tsc.rdtsc();
}

pub fn trace_lap(position: usize) void {
    if (!is_initialized) {
        return;
    }
    tracer.tracer_info.items(.end_time)[position] = tsc.rdtsc();
    tracer.tracer_info.items(.hit_count)[position] += 1;
}
const std_out = std.log.scoped(.tracer_output);

pub fn tracer_print_stdout() void {
    if (!is_initialized) {
        std.log.err("Priting tracer without initializing it\n", .{});
        return;
    }
    const slice = tracer.tracer_info.slice();
    const full_time = duration_ms(slice.items(.end_time)[root_node], slice.items(.start_time)[root_node]);
    std_out.info("Total time({s}): {d:.3} (CPU freq {d})\n", .{ slice.items(.name)[0].?, full_time, cpu_frequency });
    for (1..slice.len) |pos| {
        const mark_time = duration_ms(slice.items(.end_time)[pos], slice.items(.start_time)[pos]);
        std_out.info("\t{s}", .{slice.items(.fn_name)[pos]});
        if (slice.items(.name)[pos]) |name| {
            std_out.info("[{s}]", .{name});
        }
        std_out.info(" {d:.3} ({d.2}%)\n", .{ mark_time, mark_time * 100.0 / full_time });
    }
}

pub fn tracer_print_stderr() void {
    if (!is_initialized) {
        std.log.err("Priting tracer without initializing it\n", .{});
        return;
    }
    const slice = tracer.tracer_info.slice();
    const full_time = duration_ms(slice.items(.end_time)[root_node], slice.items(.start_time)[root_node]);
    std.debug.print("Total time({s}): {d:.6} (CPU freq {d})\n", .{ slice.items(.name)[0].?, full_time, cpu_frequency });
    for (1..slice.len) |pos| {
        const mark_time = duration_ms(slice.items(.end_time)[pos], slice.items(.start_time)[pos]);
        std.debug.print("\t{s}", .{slice.items(.fn_name)[pos]});
        if (slice.items(.name)[pos]) |name| {
            std.debug.print("[{s}]", .{name});
        }
        std.debug.print(" {d:.6} ({d:.2}%)\n", .{ mark_time, mark_time * 100.0 / full_time });
    }
}

pub fn duration(end: u64, start: u64) f64 {
    const diff: f64 = @floatFromInt(end -% start);
    return diff / cpu_frequency;
}

pub fn duration_ms(end: u64, start: u64) f64 {
    const diff: f64 = @floatFromInt(end -% start);
    return diff * 1000.0 / cpu_frequency;
}

pub fn duration_ns(end: u64, start: u64) f64 {
    const diff: f64 = @floatFromInt(end -% start);
    return diff * 1000.0 * 1000.0 / cpu_frequency;
}

test Tracer {
    try tracer_initialize(std.testing.allocator, "Tracer testing", 30, 50);
    defer tracer_shutdown();

    const t = trace(@src().fn_name, null);
    tsc.sleep(100);
    trace_end(t);

    const t2 = trace(@src().fn_name, "Second Timer");
    tsc.sleep(200);
    trace_end(t2);

    tracer_finish();
    tracer_print_stderr();
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;
const windows = std.os.windows;
const LARGE_INTEGER = windows.LARGE_INTEGER;
