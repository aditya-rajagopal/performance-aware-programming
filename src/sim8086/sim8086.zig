pub const disassemble = @import("disassemble.zig").disassemble;

comptime {
    _ = @import("disassemble.zig");
    _ = @import("decode.zig");
}
