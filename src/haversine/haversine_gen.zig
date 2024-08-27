const std = @import("std");
const utils = @import("utils");
const defines = @import("defines.zig");
const uniform = @import("uniform.zig");
const clustered = @import("clustered.zig");
const Distributions = defines.Distributions;

const usage =
    \\ 
    \\ Usage:
    \\ haversine_gen [uniform/cluster] [seed] [number of point pairs]
;

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
    var num_points = try std.fmt.parseInt(u64, num_points_str, 10);
    if (num_points > defines.MAX_POINTS) {
        std.log.warn("Number of points to generate exceeds the maximum {d}: got {d}", .{ defines.MAX_POINTS, num_points });
        num_points = defines.MAX_POINTS;
    }

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

        switch (distribution_type) {
            .uniform => uniform.init(seed),
            .clustered => {
                const num_clusters: usize = 1 + @divFloor(num_points, 64);
                const points_per_cluster: usize = @divFloor(num_points, num_clusters) + 1;
                try clustered.init(allocator, num_clusters, points_per_cluster, seed);
            },
        }

        _ = try out_buf.write("{{\"pairs\": [\n");
        const delimiter = [_][]const u8{ ",\n", "\n" };

        var average: f64 = 0;

        var x0: f64 = undefined;
        var y0: f64 = undefined;
        var x1: f64 = undefined;
        var y1: f64 = undefined;
        var distance: f64 = undefined;

        const ratio: f64 = 1 / @as(f64, @floatFromInt(num_points));

        for (0..num_points) |i| {
            switch (distribution_type) {
                .uniform => {
                    x0, y0, x1, y1 = uniform.get_point();
                },
                .clustered => {
                    x0, y0, x1, y1 = clustered.get_point();
                },
            }

            distance = defines.ReferenceHaversine(x0, y0, x1, y1, defines.EARTH_RADIUS);
            average += distance * ratio;

            _ = try out_buf_writer.print("{{\"x0\":{d},\"y0\":{d},\"x1\":{d},\"y1\":{d} }}", .{ x0, y0, x1, y1 });
            _ = try data_buf.write(std.mem.asBytes(&distance));

            const delim: usize = @intFromBool(i == num_points - 1);
            _ = try out_buf.write(delimiter[delim]);
        }

        _ = try data_buf.write(std.mem.asBytes(&average));
        _ = try out_buf.write("]");
        try out_buf.flush();
        try data_buf.flush();
        clustered.deinit();
        const end = start.read();

        std.debug.print("Average: {d}\n", .{average});
        std.debug.print("Time to generate {d} points is {s}\n", .{ num_points, std.fmt.fmtDuration(end) });
    }
}
