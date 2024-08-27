const std = @import("std");
const defines = @import("defines.zig");

const X_PATCH_LIMIT = 180.0;
const Y_PATCH_LIMIT = 90.0;

const Cluster = struct {
    range_x: struct { min: f64, range: f64 },
    range_y: struct { min: f64, range: f64 },
    generatons_left: usize,

    pub fn format(self: *const Cluster, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return writer.print(
            "Cluster{{X:(m:{d}, r:{d}), Y(m:{d}, r:{d})}}, gen: {d}",
            .{ self.range_x.min, self.range_x.range, self.range_y.min, self.range_y.range, self.generatons_left },
        );
    }
};

const ClusterData = struct {
    clusters: []Cluster,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ClusterData) void {
        self.allocator.free(self.clusters);
    }
};

var clusters: ClusterData = undefined;
var rng: std.rand.DefaultPrng = undefined;
var current_cluster: usize = 0;
var max_clusters: usize = 0;
var initalized: bool = false;

pub fn init(allocator: std.mem.Allocator, num_clusters: usize, points_per_cluster: usize, seed: u64) !void {
    if (initalized) {
        return;
    }
    var local_clusters = try std.ArrayList(Cluster).initCapacity(allocator, num_clusters);
    defer local_clusters.deinit();
    std.debug.print("Num clusters: {d}, points_per_cluster:{d}\n", .{ num_clusters, points_per_cluster });

    rng = std.rand.DefaultPrng.init(seed);
    max_clusters = num_clusters;

    var cluster: Cluster = undefined;
    var rx: f64 = undefined;
    var ry: f64 = undefined;
    var x: f64 = undefined;
    var y: f64 = undefined;
    for (0..num_clusters) |_| {
        rx = rng.random().float(f64) * X_PATCH_LIMIT;
        ry = rng.random().float(f64) * Y_PATCH_LIMIT;

        x = rng.random().float(f64) * 360.0 - 180.0;
        y = rng.random().float(f64) * 180.0 - 90.0;

        cluster.range_x.min = @max(x - rx, -180.0);
        cluster.range_x.range = @min(x + rx, 180.0) - cluster.range_x.min;
        cluster.range_y.min = @max(y - ry, -90.0);
        cluster.range_y.range = @min(y + ry, 90.0) - cluster.range_y.min;

        cluster.generatons_left = points_per_cluster;
        local_clusters.appendAssumeCapacity(cluster);
    }

    clusters = .{
        .clusters = try local_clusters.toOwnedSlice(),
        .allocator = allocator,
    };
    initalized = true;
}

pub fn deinit() void {
    if (!initalized) {
        return;
    }

    clusters.deinit();
    initalized = false;
}

// var i: usize = 0;
pub fn get_point() struct { f64, f64, f64, f64 } {
    var cluster = &clusters.clusters[current_cluster];
    if (cluster.generatons_left == 0) {
        // if (i < 20) {
        //     std.debug.print("Current: {s}\n", .{cluster.*});
        // }
        current_cluster += 1;
        // i += 1;
        cluster = &clusters.clusters[current_cluster];
        // if (i < 21) {
        //     std.debug.print("Next: {s}\n", .{cluster.*});
        // }
    }
    cluster.generatons_left -= 1;
    return .{
        rng.random().float(f64) * cluster.range_x.range + cluster.range_x.min,
        rng.random().float(f64) * cluster.range_y.range + cluster.range_y.min,
        rng.random().float(f64) * cluster.range_x.range + cluster.range_x.min,
        rng.random().float(f64) * cluster.range_y.range + cluster.range_y.min,
    };
}
