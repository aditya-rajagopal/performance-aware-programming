const std = @import("std");
const utils = @import("utils");
const haversine = @import("haversine");

var rng: std.rand.Pcg = undefined;

pub fn init(seed: u64) void {
    rng = std.rand.Pcg.init(seed);
}

pub fn get_point() struct { f64, f64, f64, f64 } {
    return .{
        (rng.random().float(f64) * 360.0 - 180.0),
        (rng.random().float(f64) * 180.0 - 90.0),
        (rng.random().float(f64) * 360.0 - 180.0),
        (rng.random().float(f64) * 180.0 - 90.0),
    };
}
