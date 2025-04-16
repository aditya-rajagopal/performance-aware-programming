pub const print_bytecode = @import("print.zig").print_bytecode;
pub const assert = @import("assert.zig").assert;
pub const comptime_assert = @import("assert.zig").comptime_assert;
pub const json = @import("json/json.zig");

pub inline fn isComptime(val: anytype) bool {
    return @typeInfo(@TypeOf(.{val})).Struct.fields[0].is_comptime;
}

fn createEnumsFromStructs(structs: anytype) type {
    const structs_type = @TypeOf(structs);
    const structs_type_info = @typeInfo(structs_type);
    if (structs_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(structs_type));
    }
    const fields = structs_type_info.@"struct".fields;

    comptime var index: usize = 0;
    comptime var pos = 0;
    inline for (fields) |field| {
        const field_type_info = @typeInfo(field.type);
        switch (field_type_info) {
            .type => {
                const T: type = @field(structs, field.name);
                const struct_info = @typeInfo(T);
                switch (struct_info) {
                    .@"struct" => |s| {
                        inline for (s.decls) |decl| {
                            if (@typeInfo(@TypeOf(@field(T, decl.name))) == .@"fn") {
                                index += 1;
                            }
                        }
                    },
                    else => {
                        @compileError("expected comptime struct type. " ++ @typeName(T));
                    },
                }
            },
            .pointer => |p| {
                if (p.size != .one) {
                    @compileError("expected comptime string. " ++ @typeName(field.type));
                }
                index += 1;
            },
            else => {
                @compileError("Expected struct or slice got: " ++ @typeName(field.type));
            },
        }
        pos += 1;
    }
    comptime var enum_fields: [index]std.builtin.Type.EnumField = undefined;

    index = 0;
    pos = 0;
    inline for (fields) |field| {
        const field_type_info = @typeInfo(field.type);
        switch (field_type_info) {
            .type => {
                const T: type = @field(structs, field.name);
                const struct_info = @typeInfo(T);
                switch (struct_info) {
                    .@"struct" => |s| {
                        inline for (s.decls) |decl| {
                            if (@typeInfo(@TypeOf(@field(T, decl.name))) == .@"fn") {
                                enum_fields[index].name = decl.name; // @typeName(T) ++ "__" ++ decl.name;
                                enum_fields[index].value = index;
                                index += 1;
                            }
                        }
                    },
                    else => {
                        @compileError("expected comptime struct type. " ++ @typeName(T));
                    },
                }
            },
            .pointer => |p| {
                if (p.size != .one) {
                    @compileError("expected Slice pointer. " ++ @typeName(structs_type));
                }
                enum_fields[index].name = @field(structs, field.name);
                enum_fields[index].value = index;
                index += 1;
            },
            else => {
                @compileError("Expected struct or slice");
            },
        }
        pos += 1;
    }
    var enum_type: std.builtin.Type.Enum = undefined;

    enum_type.fields = &enum_fields;
    enum_type.tag_type = @Type(std.builtin.Type{ .int = .{ .bits = 16, .signedness = .unsigned } });
    enum_type.decls = &[0]std.builtin.Type.Declaration{};
    enum_type.is_exhaustive = true;

    return @Type(std.builtin.Type{ .@"enum" = enum_type });
}

test createEnumsFromStructs {
    const S1 = struct {
        pub fn add() void {}
        pub fn sub() void {}
    };
    const T = createEnumsFromStructs(.{S1});
    const add: T = .add;
    const sub: T = .sub;
    try std.testing.expectEqual(0, @intFromEnum(add));
    try std.testing.expectEqual(1, @intFromEnum(sub));
}

const std = @import("std");

comptime {
    _ = @import("json/parser.zig");
    _ = @import("json/parser_new.zig");
    _ = @import("json/lexer.zig");
    _ = @import("json/json.zig");
}
