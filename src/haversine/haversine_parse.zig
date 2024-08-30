const usage =
    \\ 
    \\ Usage:
    \\ haversine_parse [buffered/full] [haversine data file *.json] [?data.bin]
;

pub const style = enum(u1) {
    buffered,
    file,
};

pub fn main() !void {
    // var start = try std.time.Timer.start();
    // var parts = try std.time.Timer.start();
    var init_time: u64 = undefined;
    var parse_time: u64 = undefined;
    var haversine_time: u64 = undefined;

    utils.instrument.calibrate_frequency(50);
    const program_start = rdtsc();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(gpa_allocator);
    defer args.deinit();
    _ = args.next().?;

    const read_style = args.next() orelse {
        std.log.err("Missing argument [buffered/file]", .{});
        std.log.err("{s}\n", .{usage});
        return;
    };

    var parse_type = style.buffered;
    if (std.mem.eql(u8, "file", read_style)) {
        parse_type = style.file;
    } else if (!std.mem.eql(u8, "buffered", read_style)) {
        std.log.err("Invalid type of reading file: {s}", .{read_style});
        std.log.err("{s}\n", .{usage});
        return;
    }

    const file_name = args.next() orelse {
        std.log.err("Missing argument [file]", .{});
        std.log.err("{s}\n", .{usage});
        return;
    };

    var file_parts = std.mem.splitScalar(u8, file_name, '_');
    _ = file_parts.next();
    const num_points_str = file_parts.next() orelse {
        std.log.err("File: {s} is not of the form data_<num_points>_distribtuion.json\n", .{file_name});
        return;
    };

    const num_points = std.fmt.parseInt(usize, num_points_str, 10) catch {
        std.log.err(
            "File: {s} is not of the form data_<num_points>_distribtuion.json. Num points is not an integer: {s}\n",
            .{ file_name, num_points_str },
        );
        return;
    };

    var have_data_file: bool = false;
    var binary_data: []const u8 = undefined;
    const data_file_name = args.next();
    if (data_file_name) |file| {
        binary_data = try std.fs.cwd().readFileAlloc(allocator, file, 5e9);
        std.debug.print("Read binary file of: {d} bytes\n", .{binary_data.len});
        have_data_file = true;
    }

    init_time = rdtsc();

    var json: JSON = undefined;

    switch (parse_type) {
        .buffered => json = try JSON.parse_file(file_name, allocator, 50 * num_points),
        .file => {
            const data = try std.fs.cwd().readFileAlloc(allocator, file_name, 5e9);
            defer allocator.free(data);
            std.debug.print("Read file of: {d} bytes\n", .{data.len});
            json = try JSON.parse_slice(data, allocator, 50 * num_points);
        },
    }
    parse_time = rdtsc();

    std.debug.print(
        "JSON: strings: {d}, nodes: {d}, extra_data: {d}\n",
        .{ json.strings.len, json.nodes.len, json.extra_data.len },
    );

    const array_nodes: JSON.Node.Array = try json.query_expect(JSON.Node.Array, "pairs", JSON.root_node);

    var average: f64 = 0;
    var avg_difference: f64 = 0;
    var num_different_points: usize = 0;
    var index: usize = 0;
    for (array_nodes) |node| {
        const p: PointPair = try json.query_struct(PointPair, node);
        const result = ReferenceHaversine(p.x0, p.y0, p.x1, p.y1, defines.EARTH_RADIUS);
        average += result;
        if (have_data_file) {
            const cached_distance = std.mem.bytesAsValue(f64, binary_data[index * 8 ..]);
            const difference = result - cached_distance.*;
            num_different_points += @intFromBool(difference > 0);
            avg_difference += difference;
            index += 1;
        }
    }
    const num_points_float = @as(f64, @floatFromInt(num_points));
    average = average / num_points_float;
    avg_difference = avg_difference / num_points_float;
    var cached_average: f64 = 0;
    if (have_data_file) {
        cached_average = std.mem.bytesAsValue(f64, binary_data[index * 8 ..]).*;
    }

    haversine_time = rdtsc();
    json.deinit();
    const full_time = rdtsc();

    const time_to_init = utils.instrument.duration(init_time, program_start);
    const time_to_parse = utils.instrument.duration(parse_time, init_time);
    const time_to_haversine = utils.instrument.duration(haversine_time, parse_time);
    const total_time = utils.instrument.duration(full_time, program_start);

    std.debug.print("Parsed JSON haversine result: {d}\n", .{average});

    if (have_data_file) {
        std.debug.print("Cached JSON haversine result: {d}\n", .{cached_average});
        std.debug.print("Average difference: {d}\n", .{avg_difference});
        std.debug.print("Number of points with different distances: {d}\n", .{num_different_points});
    }

    std.debug.print("\n", .{});

    std.debug.print("Total Time: {d:.3}ms. (CPU Frequency: {d})\n", .{ total_time * 1000.0, utils.instrument.calibrated_cpu_frequency });
    std.debug.print("\tTime to init: {d:.3}ms  ({d:.2}%)\n", .{ time_to_init * 1000.0, time_to_init * 100.0 / total_time });
    std.debug.print("\tTime to parse json: {d:.3}ms ({d:.2})%\n", .{ time_to_parse * 1000.0, time_to_parse * 100.0 / total_time });
    std.debug.print("\tTime to calculate haversine: {d:.3}ms ({d:.2}%)\n", .{ time_to_haversine * 1000.0, time_to_haversine * 100.0 / total_time });
    const printing = rdtsc();
    const printing_time = utils.instrument.duration(printing, full_time);
    std.debug.print("\tTime to print times: {d:.3}ms\n", .{printing_time * 1000.0});
}

const JSON = @import("utils").json;
const utils = @import("utils");
const rdtsc = utils.instrument.rdtsc;
const std = @import("std");
const defines = @import("defines.zig");
const PointPair = defines.PointPair;
const ReferenceHaversine = defines.ReferenceHaversine;
