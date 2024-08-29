pub const print_bytecode = @import("print.zig").print_bytecode;
pub const assert = @import("assert.zig").assert;
pub const comptime_assert = @import("assert.zig").comptime_assert;
pub const json = @import("json/json.zig");

pub inline fn isComptime(val: anytype) bool {
    return @typeInfo(@TypeOf(.{val})).Struct.fields[0].is_comptime;
}

comptime {
    _ = @import("json/parser.zig");
    _ = @import("json/lexer.zig");
    _ = @import("json/json.zig");
}
