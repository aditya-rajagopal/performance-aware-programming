pub const PointPair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,

    pub fn jsonStringify(self: *const PointPair, writer: anytype) !void {
        _ = try writer.print("{{\"x0\": {d}, \"y0\": {d}, \"x1\": {d}, \"y1\": {d} }}", .{ self.x0, self.y0, self.x1, self.y1 });
    }
};
