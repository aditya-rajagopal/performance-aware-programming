const root = @import("root");

const MAX_TRIES = 10_000_000;

const options: Options = if (@hasDecl(root, "rep_test_options")) root.rep_test_options else .{};

pub const Options = struct {
    /// Can setup a function that returns u64 time stamp counter
    time_fn: *const fn () u64 = tsc.rdtsc,
};

pub const RepType = union(enum) {
    fixed_len: u32, // contains number of steps
    min: f32, // contains time to spend before new min candidate
    fixed_time: f32, // containst the time to spend on the test
};

pub const MetricsFunction = *const fn (test_times: *Result) f64;
pub const TestFn = *const fn (*Ctx) anyerror!void;
pub const TestCase = struct {
    name: []const u8,
    function: TestFn,
    mode: RepType,
};

pub const TestCases: []const TestCase = if (@hasDecl(root, "rep_test_cases"))
    root.rep_test_cases
else
    @compileError("Using repetition tester without defining test_cases");

pub const Result = struct {
    calibrated_freq: f64 = 0,
    num_tries: u32 = 0,
    total_time: u64 = 0,
    min_time: u64 = std.math.maxInt(u64) - 1,
    max_time: u64 = 0,
    expected_bytes: u64 = 0,
    times: [MAX_TRIES]u64 = [_]u64{0} ** MAX_TRIES,
};

pub const Ctx = struct {
    state: State = .IDLE,
    test_start_time: u64 = 0,

    test_min_check_time: u64 = 0,
    mode: RepType,

    num_blk_started: u32 = 0,
    num_blk_ended: u32 = 0,

    payload: ?*anyopaque = null,

    bytes_in_run: u64 = 0,
    result: Result = .{},

    pub const State = enum {
        IDLE,
        RUNNING,
        ERROR,
    };

    pub fn reset(self: *Ctx) void {
        self.num_blk_ended = 0;
        self.num_blk_started = 0;
        self.bytes_in_run = 0;

        self.result.times = [_]u64{0} ** MAX_TRIES;
        self.result.num_tries = 0;
        self.result.min_time = std.math.maxInt(u64) - 1;
        self.result.max_time = 0;
        self.result.total_time = 0;

        self.test_start_time = options.time_fn();
        self.test_min_check_time = options.time_fn();
    }

    pub fn begin(self: *Ctx) void {
        self.num_blk_started += 1;
        self.result.times[self.result.num_tries] -%= options.time_fn();
    }

    pub fn end(self: *Ctx) void {
        self.result.times[self.result.num_tries] +%= options.time_fn();
        self.num_blk_ended += 1;
    }

    pub fn data(self: *Ctx, bytes: u64) void {
        self.bytes_in_run += bytes;
    }

    pub fn is_running(self: *Ctx) bool {
        if (self.state == .IDLE) {
            self.reset();
            self.state = .RUNNING;
            return true;
        }

        if (self.state == .RUNNING) {
            if (self.num_blk_started > 0) {
                if (self.num_blk_started != self.num_blk_ended) {
                    self.report_error(
                        "Mismatch of number of blocks started and ended in Run {d}: started: {d} vs ended: {d}\n",
                        .{ self.result.num_tries, self.num_blk_started, self.num_blk_ended },
                    );
                }

                if (self.bytes_in_run != self.result.expected_bytes) {
                    self.report_error(
                        "Mimsatch in number of bytes flowing through test in Run{d}: expected: {d} vs actual: {d}\n",
                        .{ self.result.num_tries, self.result.expected_bytes, self.bytes_in_run },
                    );
                }
            }
        }

        if (self.state == .RUNNING) {
            const current_time = options.time_fn();
            const total_time = self.result.times[self.result.num_tries];
            if (total_time > self.result.max_time) {
                self.result.max_time = total_time;
            }
            if (total_time < self.result.min_time) {
                self.test_min_check_time = current_time;
                self.result.min_time = total_time;

                const stdout = std.io.getStdOut().writer();
                print_time("New min:", total_time, self.result.calibrated_freq, self.bytes_in_run, stdout) catch unreachable;
                stdout.print("                      \r", .{}) catch unreachable;
            }
            self.result.total_time += total_time;
            self.result.num_tries += 1;

            self.num_blk_ended = 0;
            self.num_blk_started = 0;
            self.bytes_in_run = 0;

            if (self.result.num_tries >= MAX_TRIES) {
                std.log.warn(
                    "Reached maximum number of tries 10 mil. Try changing the problem statement or change the max tries\n",
                    .{},
                );
                self.state = .IDLE;
                return false;
            }

            switch (self.mode) {
                .fixed_len => |len| {
                    if (self.result.num_tries < len) {
                        return true;
                    }
                },
                .min => |reset_time| {
                    const time_since_last_min = @as(f64, @floatFromInt(current_time -% self.test_min_check_time)) / self.result.calibrated_freq;
                    if (time_since_last_min < reset_time) {
                        return true;
                    }
                },
                .fixed_time => |time| {
                    const time_since_start = @as(f64, @floatFromInt(current_time -% self.test_start_time)) / self.result.calibrated_freq;
                    if (time_since_start < time) {
                        return true;
                    }
                },
            }
            self.state = .IDLE;
        }

        return false;
    }

    pub fn report_error(self: *Ctx, comptime fmt: []const u8, args: anytype) void {
        self.state = .ERROR;
        std.log.err(fmt, args);
    }
};

pub const TestRunner = struct {
    name: []const u8,
    function: TestFn,
    context: Ctx,
};

var Tests: [TestCases.len]TestRunner = blk: {
    var runners: [TestCases.len]TestRunner = undefined;
    for (0..runners.len) |i| {
        runners[i].name = TestCases[i].name;
        runners[i].function = TestCases[i].function;
        runners[i].context = Ctx{ .mode = TestCases[i].mode };
    }
    break :blk runners;
};
var calibrated_freq: f64 = 0;

pub fn run_tests() !void {
    var is_running = true;
    var stdout = std.io.getStdOut().writer();
    var stdin = std.io.getStdIn().reader();
    var buffer: [1024]u8 = undefined;
    calibrated_freq = tsc.calibrate_frequency(50, options.time_fn);
    var round: usize = 0;
    while (is_running) {
        for (&Tests) |*case| {
            try stdout.print("-" ** 10 ++ "{s}-{d}" ++ "-" ** 10 ++ "\n", .{ case.name, round });
            case.context.result.calibrated_freq = (calibrated_freq);

            try case.function(&case.context);

            if (case.context.state == .IDLE) {
                try stdout.print("                                     \r", .{});
                try print_results(&case.context.result);
            }
            if (case.context.state == .ERROR) {
                case.context.state = .IDLE;
            }
        }
        try stdout.print("Do you want to continue? [Y/N] ", .{});
        const confirmation = try stdin.readUntilDelimiter(&buffer, '\n');
        if (confirmation.len != 2) {
            std.log.err("Unrecognized response: {s}\n", .{confirmation});
            break;
        } else if (confirmation.len == 2 and 'N' == confirmation[0]) {
            is_running = false;
        } else if (confirmation.len == 2 and confirmation[0] != 'Y') {
            std.log.err("Unrecognized response: {s}\n", .{confirmation});
            break;
        }
        round += 1;
    }
}

pub fn print_results(result: *const Result) !void {
    const stdout = std.io.getStdOut().writer();
    try print_time("Min", result.min_time, result.calibrated_freq, result.expected_bytes, stdout);
    try stdout.print("\n", .{});
    try print_time("Max", result.max_time, result.calibrated_freq, result.expected_bytes, stdout);
    try stdout.print("\n", .{});
    const avg_time = @as(f64, @floatFromInt(result.total_time)) / @as(f64, @floatFromInt(result.num_tries));
    try print_time("Average", @as(u64, @intFromFloat(avg_time)), result.calibrated_freq, result.expected_bytes, stdout);
    try stdout.print("\n", .{});
}

pub fn print_time(label: []const u8, time: u64, freq: f64, bytes: u64, stdout: anytype) !void {
    const time_in_s = as_second(time, freq);
    try stdout.print(
        "{s}: {d:.6} ms ( {d:.4} gb/s)",
        .{ label, time_in_s, @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0 * time_in_s) },
    );
}

pub fn as_second(time_counter: u64, cpu_freq: f64) f64 {
    return @as(f64, @floatFromInt(time_counter)) / cpu_freq;
}

pub fn prepare_test(id: usize, payload: ?*anyopaque, expected_bytes: u64) void {
    Tests[id].context.payload = payload;
    Tests[id].context.expected_bytes = expected_bytes;
}

pub fn prepare_all(payload: ?*anyopaque, expected_bytes: u64) void {
    for (&Tests) |*case| {
        case.context.payload = payload;
        case.context.result.expected_bytes = expected_bytes;
    }
}

const std = @import("std");
const tsc = @import("tsc.zig");
