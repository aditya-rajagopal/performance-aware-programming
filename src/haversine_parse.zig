const usage =
    \\ 
    \\ Usage:
    \\ haversine_parse [haversine data file *.json]
;

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

    var json = try JSON.parse_file(file_name, allocator, 50 * num_points);
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
