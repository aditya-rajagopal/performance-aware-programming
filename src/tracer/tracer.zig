pub const tsc = @import("tsc.zig");
const root = @import("root");

const TracerInfo = struct {
    hit_count: u32 = 0,
    scope_time_exclusive: u64 = 0,
    scope_time_inclusive: u64 = 0,
};

// NOTE: Potentially might be needed if we do buffer based solution
// const Mark = struct {
//     pos: usize,
//     time: u64,
// };

pub const options: Options = if (@hasDecl(root, "tracer_options")) root.tracer_options else .{};

pub const Options = struct {
    enabled: bool = true,
};

pub const TracerAnchors: type = if (@hasDecl(root, "TracerAnchors"))
    root.TracerAnchors
else
    enum {
        anchor0,
        anchor1,
        anchor2,
        anchor3,
        anchor4,
        anchor5,
        anchor6,
        anchor7,
    };

pub fn directEnumArrayDefault(
    comptime E: type,
    comptime Data: type,
    comptime default: ?Data,
    comptime max_unused_slots: comptime_int,
    init_values: std.enums.EnumFieldStruct(E, Data, default),
) [std.enums.directEnumArrayLen(E, max_unused_slots) + 1]Data {
    @setEvalBranchQuota(200000);
    const len = comptime std.enums.directEnumArrayLen(E, max_unused_slots) + 1;
    var result: [len]Data = if (default) |d| [_]Data{d} ** len else undefined;
    inline for (@typeInfo(@TypeOf(init_values)).Struct.fields) |f| {
        const enum_value = @field(E, f.name);
        const index = @as(usize, @intCast(@intFromEnum(enum_value)));
        result[index] = @field(init_values, f.name);
    }
    return result;
}

var tracer_anchors = directEnumArrayDefault(
    TracerAnchors,
    TracerInfo,
    TracerInfo{},
    @typeInfo(TracerAnchors).Enum.fields.len,
    .{},
);

var current_parent: usize = 0;
var is_initialized: bool = false;
var cpu_frequency: f64 = 0;
var TracerStart: u64 = 0;
var TracerEnd: u64 = 0;

const root_node: usize = 0;

pub fn tracer_initialize(calibrate_time_ms: u64) !void {
    if (is_initialized) {
        std.log.err("Trying to reinitialize Tracer\n", .{});
        return;
    }
    cpu_frequency = tsc.calibrate_frequency(calibrate_time_ms);
    TracerStart = tsc.rdtsc();
    is_initialized = true;
}

pub fn tracer_finish() void {
    TracerEnd = tsc.rdtsc();
}

pub fn trace(comptime E: TracerAnchors) type {
    if (!options.enabled) {
        return struct {
            pub fn start() @This() {
                return .{};
            }

            pub fn end(self: @This()) void {
                _ = self;
            }
        };
    }
    const position = @intFromEnum(E) + 1;
    return struct {
        start_time: u64,
        inlcusive: u64,
        parent: usize,

        const Self = @This();
        pub fn start() Self {
            var local: Self = undefined;
            local.parent = current_parent;
            current_parent = position;
            local.inlcusive = tracer_anchors[position].scope_time_inclusive;
            local.start_time = tsc.rdtsc();
            return local;
        }

        pub fn end(self: Self) void {
            const elapsed_time = tsc.rdtsc() - self.start_time;
            tracer_anchors[position].hit_count += 1;
            tracer_anchors[position].scope_time_exclusive +%= elapsed_time;
            tracer_anchors[self.parent].scope_time_exclusive -%= elapsed_time;
            tracer_anchors[position].scope_time_inclusive = self.inlcusive + elapsed_time;

            current_parent = self.parent;
        }
    };
}

pub fn tracer_print_stderr() void {
    if (!is_initialized) {
        std.log.err("Priting tracer without initializing it\n", .{});
        return;
    }
    const full_time = duration_ms(TracerEnd, TracerStart);
    std.debug.print("Total time: {d:.6} (CPU freq {d})\n", .{ full_time, cpu_frequency });
    inline for (@typeInfo(TracerAnchors).Enum.fields) |field| {
        const info = tracer_anchors[field.value + 1];
        const mark_time = to_ms(info.scope_time_exclusive);
        if (mark_time != 0) {
            std.debug.print("\t{s}[{d}]\n", .{ field.name, info.hit_count });
            std.debug.print(
                "\t\t{d:.6} ({d:.2}%)\t{d:.6}ms/hit\n",
                .{ mark_time, mark_time * 100.0 / full_time, mark_time / @as(f64, @floatFromInt(info.hit_count)) },
            );

            if (info.scope_time_inclusive != info.scope_time_exclusive) {
                const child_time = to_ms(info.scope_time_inclusive);
                std.debug.print("\t\t( {d:.6} ({d:.2}%) with children)\n", .{ child_time, child_time * 100.0 / full_time });
            }
        }
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

pub fn to_ms(time_counter: u64) f64 {
    return @as(f64, @floatFromInt(time_counter)) * 1000.0 / cpu_frequency;
}

test "Tracer" {
    try tracer_initialize(50);

    var v = trace(.anchor1).start();
    tsc.sleep(100);
    v.end();

    v = trace(.anchor1).start();
    tsc.sleep(200);
    v.end();

    const anchor = tracer_anchors[@intFromEnum(TracerAnchors.anchor1) + 1];
    std.debug.print("Anchor1: {d}, {d}", .{ to_ms(anchor.scope_time_exclusive), anchor.hit_count });
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;
const windows = std.os.windows;
const LARGE_INTEGER = windows.LARGE_INTEGER;
