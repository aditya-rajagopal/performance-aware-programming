pub var calibrated_cpu_frequency: f64 = 0;
var is_initialized: bool = false;

pub fn query_performance_frequency() u64 {
    var result: LARGE_INTEGER = 0;
    _ = windows.ntdll.RtlQueryPerformanceFrequency(&result);
    return @as(u64, @bitCast(result));
}

pub fn query_performance_counter() u64 {
    var result: LARGE_INTEGER = 0;
    _ = windows.ntdll.RtlQueryPerformanceCounter(&result);
    return @as(u64, @bitCast(result));
}

pub fn rdtsc() u64 {
    var low: u32 = 0;
    var hi: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, @intCast(hi)) << 32) | @as(u64, @intCast(low));
}

pub fn calibrate_frequency(ms: u64) void {
    if (is_initialized) {
        return;
    }
    const freq: u64 = query_performance_frequency();
    const ticks_to_run = ms * @divFloor(freq, 1000);
    const cpu_start = rdtsc();
    const start = query_performance_counter();

    while (query_performance_counter() -% start < ticks_to_run) {}

    const end = query_performance_counter();
    const cpu_end = rdtsc();

    const cpu_elapsed = cpu_end -% cpu_start;
    const os_elpased = end -% start;

    const cpu_freq = freq * cpu_elapsed / os_elpased;
    calibrated_cpu_frequency = @floatFromInt(cpu_freq);
    is_initialized = true;
}

pub fn duration(end: u64, start: u64) f64 {
    const diff: f64 = @floatFromInt(end -% start);
    return diff / calibrated_cpu_frequency;
}

test rdtsc {
    calibrate_frequency(50);
}

const std = @import("std");
const time = std.time;
const windows = std.os.windows;
const LARGE_INTEGER = windows.LARGE_INTEGER;
