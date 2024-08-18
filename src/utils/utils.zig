pub const print_bytecode = @import("print.zig").print_bytecode;
pub const assert = @import("assert.zig").assert;

pub inline fn isComptime(val: anytype) bool {
    return @typeInfo(@TypeOf(.{val})).Struct.fields[0].is_comptime;
}
