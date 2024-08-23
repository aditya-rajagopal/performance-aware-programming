pub const disassemble = @import("disassemble.zig").disassemble;
pub const simulate = @import("vm.zig").simulate;

comptime {
    _ = @import("disassemble.zig");
    _ = @import("decode.zig");
    _ = @import("vm.zig");
}
