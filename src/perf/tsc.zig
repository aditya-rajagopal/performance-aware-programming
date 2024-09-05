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

pub fn sleep(ms: u64) void {
    const freq: u64 = query_performance_frequency();
    const ticks_to_run = ms * @divFloor(freq, 1000);
    const start = query_performance_counter();

    while (query_performance_counter() -% start < ticks_to_run) {}
}

pub fn calibrate_frequency(ms: u64, time_fn: *const fn () u64) f64 {
    const freq: u64 = query_performance_frequency();
    const ticks_to_run = ms * (freq / 1000);

    const cpu_start = time_fn();
    const start = query_performance_counter();

    while (query_performance_counter() -% start < ticks_to_run) {}

    const end = query_performance_counter();
    const cpu_end = time_fn();

    const cpu_elapsed = cpu_end -% cpu_start;
    const os_elpased = end -% start;

    const cpu_freq = freq * cpu_elapsed / os_elpased;
    return @floatFromInt(cpu_freq);
}

test rdtsc {
    _ = calibrate_frequency(50, rdtsc);
}

const std = @import("std");
const time = std.time;
const windows = std.os.windows;
const LARGE_INTEGER = windows.LARGE_INTEGER;
