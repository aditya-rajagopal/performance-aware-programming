pub const JSON = @This();
strings: []const u8,
nodes: NodeArray.Slice,
extra_data: []NodeIndex,
allocator: Allocator,

pub const NodeArray = std.MultiArrayList(Node);
pub const DataArray = std.ArrayList(NodeIndex);

pub const NodeIndex = u32;
pub const StringPtr = NodeIndex;

pub const root_node = 0;

pub fn deinit(self: *JSON) void {
    self.allocator.free(self.strings);
    self.nodes.deinit(self.allocator);
    self.allocator.free(self.extra_data);
}

pub fn parse_file(file_name: []const u8, allocator: std.mem.Allocator, expected_capacity: usize) Parser.ParserError!JSON {
    var parser = try Parser.init(file_name, allocator, expected_capacity);

    try parser.parse();

    const json = JSON{
        .extra_data = try parser.extra_data.toOwnedSlice(),
        .strings = try parser.string_store.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .allocator = allocator,
    };

    parser.deinit();
    // allocator.destroy(parser);

    return json;
}

pub fn read_extra(self: *JSON, T: type, loc: usize) Allocator.Error!T {
    const type_info = @typeInfo(T);
    const extra_data = self.extra_data;
    const data_ptr = extra_data[loc..];

    switch (type_info) {
        .Int => |i| {
            comptime comptime_assert(
                i.bits == 64 and i.signedness == .signed,
                "Int read from extra data array must be i64 : got {d}bit {s} integer\n",
                .{ i.bits, @tagName(i.signedness) },
            );
            const value: i64 = @bitCast(data_ptr[0..2].*);
            return value;
        },
        .Float => |f| {
            comptime comptime_assert(
                f.bits == 64,
                "Float read from extra data array must be f64: got f{d}\n",
                .{f.bits},
            );
            const value: f64 = @bitCast(data_ptr[0..2].*);
            return value;
        },
        .Pointer => |p| {
            comptime comptime_assert(
                p.size == .Slice and p.child == u32,
                "Pointers of type []u32 are allowed: got {s} of type {any}\n",
                .{ @tagName(p.size), p.child },
            );
            const len = data_ptr[0];
            return data_ptr[1 .. len + 1];
        },
        .Array => |a| {
            comptime comptime_assert(
                a.len == 2 and a.child == u32,
                "Only returning [2]u32: got {d}[{any}]",
                .{ a.len, a.child },
            );
            return data_ptr[0..2].*;
        },
        else => {
            @compileError("Cannot read extra data of given type");
        },
    }
}

pub const Node = struct {
    key: StringPtr,
    tag: Tag,
    data: Data,

    pub const Data = u64;

    pub const Float = f64;
    pub const Integer = i64;
    pub const Dict = []NodeIndex;
    pub const Array = []NodeIndex;

    pub const Tag = enum(u8) {
        /// Extra data array stores [N + 1] elements where
        /// N is the value at the index that the data points to
        /// N, element1, ..., elementN
        json,
        /// Extra data array stores i64 as [2]u32 or u64
        /// read as u64 and use bitcast
        integer,
        /// Extra data array stores f64 as [2]u32 or u64
        /// read as u64 and use bitcast
        float,
        /// Extra data array stores start, end
        string,
        /// Extra data array stores [N + 1] Values
        /// N is the value at the index that data points to
        /// N, value1, value2, ..., valueN
        array,
        /// Stores nothing
        boolean_true,
        /// stores nothing
        boolean_false,
        /// data does not point to anything
        null,
    };
};

const std = @import("std");
const Parser = @import("parser.zig");
const Allocator = std.mem.Allocator;
const comptime_assert = @import("utils").comptime_assert;
