const usage =
    \\ 
    \\ Usage:
    \\ haversine_parse [buffered/full] [haversine data file *.json] [?data.bin]
;

pub const style = enum(u1) {
    buffered,
    file,
};

pub const TracerAnchors = enum {
    init,
    file_read,
    json_parse_read_file,
    json_parse,
    json_object,
    json_entry,
    json_token,
    query,
    haversine_parse,
};

// pub const tracer_options = .{
//     .enabled = false,
// };

pub fn main() !void {
    std.debug.print("{any}\n", .{tracer.TracerAnchors});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try tracer.tracer_initialize(50);

    const init = tracer.trace(.init).start();

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

    // _ = try allocator.alloc(u8, num_points * 50 * 30);
    // _ = arena.reset(.retain_capacity);

    init.end();

    const data_file_read = tracer.trace(.file_read).start();
    if (data_file_name) |file| {
        binary_data = try std.fs.cwd().readFileAlloc(allocator, file, 5e9);
        have_data_file = true;
    }
    data_file_read.end();

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

    std.debug.print(
        "JSON: strings: {d}, nodes: {d}, extra_data: {d}\n",
        .{ json.strings.len, json.nodes.len, json.extra_data.len },
    );

    const query_array = tracer.trace(.query).start();
    const array_nodes: JSON.Node.Array = try json.query_expect(JSON.Node.Array, "pairs", JSON.root_node);
    query_array.end();

    var average: f64 = 0;
    var avg_difference: f64 = 0;
    var num_different_points: usize = 0;
    var index: usize = 0;

    const calcs = tracer.trace(.haversine_parse).start();
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

    calcs.end();

    json.deinit();

    std.debug.print("Parsed JSON haversine result: {d}\n", .{average});

    if (have_data_file) {
        std.debug.print("Cached JSON haversine result: {d}\n", .{cached_average});
        std.debug.print("Average difference: {d}\n", .{avg_difference});
        std.debug.print("Number of points with different distances: {d}\n", .{num_different_points});
    }

    tracer.tracer_finish();
    tracer.tracer_print_stderr();
}

const JSON = @import("utils").json;
const utils = @import("utils");
const tracer = @import("tracer");
const std = @import("std");
const defines = @import("defines.zig");
const PointPair = defines.PointPair;
const ReferenceHaversine = defines.ReferenceHaversine;
