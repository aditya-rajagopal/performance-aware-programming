pub const tracer = @import("tracer.zig");
pub const rep_test = @import("rep_test.zig");
pub const tsc = @import("tsc.zig");

comptime {
    _ = @import("tracer.zig");
    _ = @import("rep_test.zig");
    _ = @import("tsc.zig");
}
