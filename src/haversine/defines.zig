pub const MAX_POINTS = 100_000_000;
pub const EARTH_RADIUS = 6372.8;

pub const PointPair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

pub const Distributions = enum {
    uniform,
    clustered,
};

fn Square(A: f64) f64 {
    const Result: f64 = (A * A);
    return Result;
}

pub fn ReferenceHaversine(x0: f64, y0: f64, x1: f64, y1: f64, radius: f64) f64 {
    var lat1: f64 = y0;
    var lat2: f64 = y1;
    const lon1: f64 = x0;
    const lon2: f64 = x1;

    const dLat: f64 = RadiansFromDegrees(lat2 - lat1);
    const dLon: f64 = RadiansFromDegrees(lon2 - lon1);

    lat1 = RadiansFromDegrees(lat1);
    lat2 = RadiansFromDegrees(lat2);

    const a: f64 = Square(sin(dLat / 2.0)) + cos(lat1) * cos(lat2) * Square(sin(dLon / 2.0));
    const c: f64 = 2.0 * asin(sqrt(a));

    const result: f64 = radius * c;

    return result;
}

const std = @import("std");
const RadiansFromDegrees = std.math.degreesToRadians;
const sin = std.math.sin;
const asin = std.math.asin;
const cos = std.math.cos;
const sqrt = std.math.sqrt;
