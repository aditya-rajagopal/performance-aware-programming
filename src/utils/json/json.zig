pub const JSON = @This();
strings: []const u8,
nodes: NodeArray.Slice,
extra_data: []NodeIndex,
allocator: Allocator,

pub const NodeArray = std.MultiArrayList(Node);
pub const DataArray = std.ArrayList(NodeIndex);

pub const NodeIndex = u32;

pub const root_node = 0;

pub const Error = error{ KeyNotFound, InvalidJson, QueryingNonObject, TypeMisatch };

pub fn deinit(self: *JSON) void {
    self.allocator.free(self.strings);
    self.nodes.deinit(self.allocator);
    self.allocator.free(self.extra_data);
}

pub fn parse_file(file_name: []const u8, allocator: std.mem.Allocator, expected_capacity: usize, file_size: u64) Parser.ParserError!JSON {
    var p = tracer.trace(.json_parse_read_file, 0).start();
    var parser = try Parser.init(file_name, allocator, expected_capacity);
    p.end();

    var p2 = tracer.trace(.json_parse, null).start(file_size);
    try parser.parse();
    p2.end();

    const json = JSON{
        .extra_data = try parser.extra_data.toOwnedSlice(),
        .strings = try parser.string_store.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .allocator = allocator,
    };

    parser.deinit();

    return json;
}

pub fn parse_slice(source: []u8, allocator: std.mem.Allocator, expected_capacity: usize) Parser.ParserError!JSON {
    var parser = try Parser.initSlice(source, allocator, expected_capacity);

    try parser.parse();

    const json = JSON{
        .extra_data = try parser.extra_data.toOwnedSlice(),
        .strings = try parser.string_store.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .allocator = allocator,
    };

    parser.deinit();

    return json;
}

pub fn parse_new(source: []const u8, allocator: std.mem.Allocator, expected_capacity: usize, comptime config: ParserN.ParserConfig) !JSON {
    return ParserN.parse(source, allocator, expected_capacity, config);
}

pub fn get_storage_size(self: *JSON) usize {
    var size: usize = 0; // in bytes
    size += self.strings.len;
    size += self.extra_data.len * 4;
    size += self.nodes.items(.key).len * 8;
    size += self.nodes.items(.tag).len;
    size += self.nodes.items(.data).len * 8;
    return size;
}

pub fn query(self: *JSON, key: []const u8, object_location: NodeIndex) Error!?NodeIndex {
    const object = self.nodes.get(object_location);
    if (object.tag != .object) {
        std.log.err("Cannot query JSON node of type: {s} expected type: object\n", .{@tagName(object.tag)});
        return Error.QueryingNonObject;
    }

    const object_entries: Node.Object = self.read_extra(Node.Object, object.data);

    var key_location: Node.String = undefined;
    var found: bool = false;
    var data_location: NodeIndex = undefined;

    for (object_entries) |entry| {
        key_location = self.nodes.items(.key)[entry];
        if (std.mem.eql(u8, self.strings[key_location[0]..key_location[1]], key)) {
            found = true;
            data_location = entry;
        }
    }

    if (!found) {
        return null;
    }

    if (data_location == root_node) {
        std.log.err("Object Node @ {d} somehow references root_node. This is an invalid json", .{object_location});
        return Error.InvalidJson;
    }

    return data_location;
}

// TODO: Change this function to accept a struct for objects and array of value types for Arrays
// And remove the query_struct function. Just this 1 fucntion should be enough.
pub fn query_expect(self: *JSON, T: type, key: []const u8, object_location: NodeIndex) JSON.Error!T {
    const entry = (try self.query(key, object_location)) orelse {
        return Error.KeyNotFound;
    };

    const value: u64 = self.nodes.items(.data)[entry];
    const value_tag: Node.Tag = self.nodes.items(.tag)[entry];

    comptime var type_info = @typeInfo(T);
    inline while (true) {
        switch (type_info) {
            .Optional => |o| {
                const child_type = o.child;
                if (value_tag == .null) {
                    return null;
                }
                type_info = @typeInfo(child_type);
                continue;
            },
            .Int => |i| {
                comptime comptime_assert(
                    i.bits == 64 and i.signedness == .signed,
                    "Can only read 64bit signed integer from JSON: got {d}bit {s} integer\n",
                    .{ i.bits, @tagName(i.signedness) },
                );
                if (value_tag != .integer) {
                    std.log.err(
                        "JSON entry with key: {s} has value of type: JSON.{s} but requested {any}\n",
                        .{ key, @tagName(value_tag), T },
                    );
                    return Error.TypeMisatch;
                }
                return @bitCast(value);
            },
            .Float => |f| {
                comptime comptime_assert(
                    f.bits == 64,
                    "Can only read f64 as array values: got f{d}\n",
                    .{f.bits},
                );
                if (value_tag != .float) {
                    std.log.err(
                        "JSON entry with key: {s} has value of type: JSON.{s} but requested {any}\n",
                        .{ key, @tagName(value_tag), T },
                    );
                    return Error.TypeMisatch;
                }
                return @bitCast(value);
            },
            .Pointer => |p| {
                comptime comptime_assert(
                    p.size == .Slice and p.child == u32,
                    "Pointers of type []u32 are allowed: got {s} of type {any}\n",
                    .{ @tagName(p.size), p.child },
                );
                if (value_tag != .array) {
                    std.log.err(
                        "JSON entry with key: {s} has value of type: JSON.{s} but requested {any}\n",
                        .{ key, @tagName(value_tag), T },
                    );
                    return Error.TypeMisatch;
                }
                const data_ptr = self.extra_data[value..];
                const len = data_ptr[0];
                return data_ptr[1 .. len + 1];
            },
            .Bool => {
                if (value_tag != .boolean_true or value_tag != .boolean_false) {
                    std.log.err(
                        "JSON entry with key: {s} has value of type: JSON.{s} but requested {any}\n",
                        .{ key, @tagName(value_tag), T },
                    );
                    return Error.TypeMisatch;
                }
                if (value == 1) {
                    return true;
                } else {
                    return false;
                }
            },
            else => {
                comptime_assert(false, "JSON value cannot be coerced to type: {any}", .{T});
            },
        }
    }
}

pub fn query_struct(self: *JSON, T: type, object_location: NodeIndex) !T {
    const object_tag = self.nodes.items(.tag)[object_location];
    if (object_tag != .object) {
        std.log.err("Cannot convert json node of type: {s} expected type: object\n", .{@tagName(object_tag)});
        return Error.QueryingNonObject;
    }

    const type_info = @typeInfo(T);
    switch (type_info) {
        .Struct => |s| {
            var output: T = undefined;
            inline for (s.fields) |field| {
                const value = self.query_expect(field.type, field.name, object_location) catch |err| switch (err) {
                    Error.KeyNotFound => escape: {
                        if (field.default_value) |default| {
                            const temp_value: *const field.type = @alignCast(@ptrCast(default));
                            break :escape temp_value.*;
                        }
                        return Error.KeyNotFound;
                    },
                    else => |overflow| return overflow,
                };
                @field(output, field.name) = value;
            }
            return output;
        },
        else => {
            comptime_assert(false, "JSON object cannot be coerced to type: {any}", .{T});
        },
    }
}

pub fn read_extra(self: *JSON, T: type, loc: usize) T {
    assert(
        loc < self.extra_data.len,
        "Trying to read from location that exceeds length of extra data: {d} max is {d}",
        .{ loc, self.extra_data.len },
    );
    const type_info = @typeInfo(T);
    const data_ptr = self.extra_data[loc..];

    switch (type_info) {
        // .Int => |i| {
        //     comptime comptime_assert(
        //         i.bits == 64 and i.signedness == .signed,
        //         "Int read from extra data array must be i64 : got {d}bit {s} integer\n",
        //         .{ i.bits, @tagName(i.signedness) },
        //     );
        //     const value: i64 = @bitCast(data_ptr[0..2].*);
        //     return value;
        // },
        // .Float => |f| {
        //     comptime comptime_assert(
        //         f.bits == 64,
        //         "Float read from extra data array must be f64: got f{d}\n",
        //         .{f.bits},
        //     );
        //     const value: f64 = @bitCast(data_ptr[0..2].*);
        //     return value;
        // },
        .Pointer => |p| {
            comptime comptime_assert(
                p.size == .Slice and p.child == u32,
                "Pointers of type []u32 are allowed: got {s} of type {any}\n",
                .{ @tagName(p.size), p.child },
            );
            const len = data_ptr[0];
            return data_ptr[1 .. len + 1];
        },
        // .Array => |a| {
        //     comptime comptime_assert(
        //         a.len == 2 and a.child == u32,
        //         "Only returning [2]u32: got {d}[{any}]",
        //         .{ a.len, a.child },
        //     );
        //     return data_ptr[0..2].*;
        // },
        else => {
            @compileError("Cannot read extra data of given type");
        },
    }
}

pub fn format(self: JSON, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print(
        "Strings: {s}\n",
        .{self.strings},
    );

    for (0..self.nodes.len) |i| {
        try writer.print(
            "Node[{d}]: {s}\n",
            .{ i, self.nodes.get(i) },
        );
    }

    try writer.print(
        "extra data: {d}\n",
        .{self.extra_data},
    );
}

pub const Node = struct {
    key: String,
    tag: Tag,
    data: Data,

    pub const Data = u64;

    pub const Float = f64;
    pub const Integer = i64;
    pub const Object = []NodeIndex;
    pub const Array = []NodeIndex;
    pub const String = [2]NodeIndex;
    pub const Boolean = bool;
    pub const None = void;

    pub const Tag = enum(u8) {
        /// Extra data array stores [N + 1] elements where
        /// N is the value at the index that the data points to
        /// N, element1, ..., elementN
        /// Value points to location of N
        object,
        /// bitcast value field to i64
        integer,
        /// bitcast value field to f64
        float,
        /// Extra data array stores start, end
        /// Value points to the location of start
        string,
        /// Extra data array stores [N + 1] Values
        /// N is the value at the index that data points to
        /// N, value1, value2, ..., valueN
        /// Value field points to location of N
        array,
        /// Stores nothing
        boolean_true,
        /// stores nothing
        boolean_false,
        /// data does not point to anything
        null,
    };

    pub fn format(self: *const Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.tag) {
            .float => {
                try writer.print(
                    "Node{{" ++ "key:({d}, {d}), tag:{s}, data:{d}" ++ "}}",
                    .{
                        self.key[0],
                        self.key[1],
                        @tagName(self.tag),
                        @as(f64, @bitCast(self.data)),
                    },
                );
            },
            .string => {
                const data = @as([2]u32, @bitCast(self.data));
                try writer.print(
                    "Node{{" ++ "key:({d}, {d}), tag:{s}, data:({d}, {d})" ++ "}}",
                    .{
                        self.key[0],
                        self.key[1],
                        @tagName(self.tag),
                        data[0],
                        data[1],
                    },
                );
            },
            else => {
                try writer.print(
                    "Node{{" ++ "key:({d}, {d}), tag:{s}, data:{d}" ++ "}}",
                    .{
                        self.key[0],
                        self.key[1],
                        @tagName(self.tag),
                        self.data,
                    },
                );
            },
        }
    }
};

// test "JSON and struct" {
//     const test_struct = struct {
//         pi: f64,
//         e: f64,
//     };
//
//     const test_json: []const u8 =
//         \\{"test": {"pi": 3.1415, "e": 2.717 }}
//     ;
//     const expected: test_struct = .{ .e = 2.717, .pi = 3.1415 };
//     const buffer = try testing.allocator.dupe(u8, test_json);
//     defer testing.allocator.free(buffer);
//     var json = try parse_slice(buffer, std.testing.allocator, 10);
//     defer json.deinit();
//
//     const test_value = (try json.query("test", root_node)).?;
//     const output = try json.query_struct(test_struct, test_value);
//     try testing.expectEqualDeep(expected, output);
// }
//
// test "JSON and struct with optional field" {
//     const test_struct = struct {
//         pi: f64,
//         e: f64,
//         i: ?f64,
//     };
//
//     const test_json: []const u8 =
//         \\{"test": {"e": 2.717, "i": null, "pi": 3.1415 }}
//     ;
//     const expected: test_struct = .{ .e = 2.717, .pi = 3.1415, .i = null };
//     const buffer = try testing.allocator.dupe(u8, test_json);
//     defer testing.allocator.free(buffer);
//     var json = try parse_slice(buffer, std.testing.allocator, 10);
//     defer json.deinit();
//
//     const test_value = (try json.query("test", root_node)).?;
//     const output = try json.query_struct(test_struct, test_value);
//     try testing.expectEqualDeep(expected, output);
// }
//
// test "JSON and struct with default parameter value" {
//     const test_struct = struct {
//         pi: f64 = 3.1415,
//         e: f64,
//         i: ?f64 = null,
//     };
//
//     const test_json: []const u8 =
//         \\{"test": {"e": 2.717 }}
//     ;
//     const expected: test_struct = .{ .e = 2.717, .pi = 3.1415, .i = null };
//     const buffer = try testing.allocator.dupe(u8, test_json);
//     defer testing.allocator.free(buffer);
//     var json = try parse_slice(buffer, std.testing.allocator, 10);
//     defer json.deinit();
//
//     const test_value = (try json.query("test", root_node)).?;
//     const output = try json.query_struct(test_struct, test_value);
//     try testing.expectEqualDeep(expected, output);
// }

const std = @import("std");
const tracer = @import("perf").tracer;
const testing = std.testing;
const Parser = @import("parser.zig");
const ParserN = @import("parser_new.zig");
const Allocator = std.mem.Allocator;
const comptime_assert = @import("../assert.zig").comptime_assert;
const assert = @import("../assert.zig").assert;
