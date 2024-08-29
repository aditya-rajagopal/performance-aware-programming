const usage =
    \\ 
    \\ Usage:
    \\ haversine_parse [buffered/full] [haversine data file *.json]
;

pub const style = enum(u1) {
    buffered,
    file,
};

pub fn main() !void {
    var start = try std.time.Timer.start();
    var parts = try std.time.Timer.start();

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

    var init_time: u64 = undefined;
    var finish_time: u64 = undefined;

    init_time = parts.lap();

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
    std.debug.print(
        "Strings: {s}\n",
        .{json.strings},
    );
    json.deinit();
    finish_time = parts.read();
    const end = start.read();
    std.debug.print("Time to init: {s}\n", .{std.fmt.fmtDuration(init_time)});
    std.debug.print("Time to parse json: {s}\n", .{std.fmt.fmtDuration(finish_time)});
    std.debug.print("Total: {s}\n", .{std.fmt.fmtDuration(end)});
}

const JSON = @import("utils").json;
const std = @import("std");
