const std = @import("std");
const utils = @import("utils");
const haversine = @import("haversine");

const MAX_POINTS = 1000;
const EarthRadius = 6372.8;

const usage =
    \\ 
    \\ Usage:
    \\ haversine_gen [uniform/cluster] [seed] [number of point pairs]
;

const Distributions = enum {
    uniform,
    clustered,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next().?;

    const distribution = args.next();
    var distribution_type = Distributions.uniform;
    if (distribution) |dist| {
        if (std.mem.eql(u8, dist, "clustered")) {
            distribution_type = Distributions.clustered;
        } else if (!std.mem.eql(u8, dist, "uniform")) {
            std.log.err("Unkown distribution type: {s}\n", .{dist});
            std.log.err("{s}\n", .{usage});
            return;
        }
    } else {
        std.log.err("{s}\n", .{usage});
        return;
    }

    const seed_str = args.next() orelse {
        std.log.err("Missing argument seed\n", .{});
        std.log.err("{s}\n", .{usage});
        return;
    };
    const seed = try std.fmt.parseInt(u64, seed_str, 10);

    const num_points_str = args.next() orelse {
        std.log.err("Missing argument seed\n", .{});
        std.log.err("{s}\n", .{usage});
        return;
    };
    const num_points = try std.fmt.parseInt(u64, num_points_str, 10);

    {
        var buffer: [1024]u8 = undefined;
        var file_name = try std.fmt.bufPrint(&buffer, "./data_{d}_{s}.json", .{ num_points, @tagName(distribution_type) });
        var start = try std.time.Timer.start();
        var out_file = try std.fs.cwd().createFile(file_name, .{});
        defer out_file.close();
        const out_writer = out_file.writer();
        var out_buf = std.io.BufferedWriter(1024000, @TypeOf(out_writer)){ .unbuffered_writer = out_writer };
        var out_buf_writer = out_buf.writer();

        file_name = try std.fmt.bufPrint(&buffer, "./data_{d}_{s}_data.bin", .{ num_points, @tagName(distribution_type) });
        var data_file = try std.fs.cwd().createFile(file_name, .{});
        defer data_file.close();
        const data_writer = data_file.writer();
        var data_buf = std.io.BufferedWriter(1024000, @TypeOf(out_writer)){ .unbuffered_writer = data_writer };

        var rng = std.rand.Pcg.init(seed);

        _ = try out_buf.write("{{\"pairs\": [\n");
        const delimiter = [_][]const u8{ ",\n", "\n" };

        var average: f64 = 0;

        for (0..num_points) |i| {
            const x0 = (rng.random().float(f64) * 360.0 - 180.0);
            const y0 = (rng.random().float(f64) * 180.0 - 90.0);
            const x1 = (rng.random().float(f64) * 360.0 - 180.0);
            const y1 = (rng.random().float(f64) * 180.0 - 90.0);

            const distance = haversine.ReferenceHaversine(x0, y0, x1, y1, EarthRadius);
            average += distance;

            _ = try out_buf_writer.print("{{\"x0\":{d},\"y0\":{d},\"x1\":{d},\"y1\":{d} }}", .{ x0, y0, x1, y1 });
            _ = try data_buf.write(std.mem.asBytes(&distance));

            const delim: usize = @intFromBool(i == num_points - 1);
            _ = try out_buf.write(delimiter[delim]);
        }

        average = average / @as(f64, @floatFromInt(num_points));
        _ = try data_buf.write(std.mem.asBytes(&average));
        _ = try out_buf.write("]");
        try out_buf.flush();
        try data_buf.flush();
        const end = start.read();

        std.debug.print("Average: {d}\n", .{average});
        std.debug.print("Time to generate {d} points is {s}\n", .{ num_points, std.fmt.fmtDuration(end) });
    }
}
