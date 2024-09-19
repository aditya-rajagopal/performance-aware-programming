// Go through the source sequentially in a for loop and treat it like a state machine
//
// Read part of the file and start parsing it character by character.
// States:
//      object_start
//      object_end
//      array_start
//      array_end
//      pair_start
//          key
//          value
//      pair_end
//      number
//      string
//      keyword?
//          null
//          true
//          false
//
// If we reach the end of file while in any state try to read the chunk of data
// Swap buffers?
pub const BUFFER_SIZE = 4096 * 32;
pub const INDEX_TYPE = u32;

pub const Parser = @This();

allocator: std.mem.Allocator,
buffer: []const u8,
state_stack: [1024]state = [_]state{.unkown} ** 1024,
extra_data: std.ArrayList(NodeIndex),

index: usize = 0,
stack_ptr: usize = 0,

string_map: JsonStringMap,

pub const JsonStringMap = std.StringHashMap(JSON.Node.String);
pub const NodeIndex = u32;

pub const state = union(enum) {
    json_start,
    object_start,
    object_end: NodeIndex,
    element_start,
    element_end: NodeIndex,
    array_start,
    array_mid: NodeIndex,
    array_end: NodeIndex,
    expected_token: u8,
    string,
    value,
    number,
    null,
    true,
    false,
    padding,
    unkown,
};

const ParserError = error{ MaxDepth, InvalidJSON };

pub fn push_state(self: *Parser, s: state) !void {
    if (self.stack_ptr > 1024) {
        return ParserError.MaxDepth;
    }
    self.state_stack[self.stack_ptr] = s;
    self.stack_ptr += 1;
}

pub fn pop_state(self: *Parser) state {
    std.debug.assert(self.stack_ptr > 0);
    self.stack_ptr -= 1;
    return self.state_stack[self.stack_ptr];
}

pub fn current_state(self: *Parser) state {
    std.debug.assert(self.stack_ptr != 0);
    return self.state_stack[self.stack_ptr - 1];
}

fn add_extra(self: *Parser, data: anytype) std.mem.Allocator.Error!NodeIndex {
    const typeinfo = @typeInfo(@TypeOf(data));
    var data_slice: []const u32 = undefined;

    const result = @as(u32, @intCast(self.extra_data.items.len));

    switch (typeinfo) {
        .Int => |i| {
            _ = i;
            // comptime comptime_assert(
            //     i.bits == 64 and i.signedness == .signed,
            //     "Int written to extra data array must be i64 : got {d}bit {s} integer\n",
            //     .{ i.bits, @tagName(i.signedness) },
            // );
            try self.extra_data.ensureUnusedCapacity(2);
            const ptr = @as([*]u32, @ptrCast(@constCast(&data)));
            data_slice = ptr[0..2];
        },
        .Float => |f| {
            _ = f;
            // comptime comptime_assert(
            //     f.bits == 64,
            //     "Float written to extra data array must be f64: got f{d}\n",
            //     .{f.bits},
            // );
            try self.extra_data.ensureUnusedCapacity(2);
            var float_data: u64 = @bitCast(data);
            const ptr = @as([*]u32, @ptrCast(&float_data));
            data_slice = ptr[0..2];
        },
        .Pointer => |p| {
            _ = p;
            // comptime comptime_assert(
            //     p.size == .Slice and p.child == u32,
            //     "Pointers of type []u32 are allowed: got {s} of type {any}\n",
            //     .{ @tagName(p.size), p.child },
            // );
            try self.extra_data.ensureUnusedCapacity(data.len + 1);
            self.extra_data.appendAssumeCapacity(@as(u32, @intCast(data.len)));
            data_slice = data;
        },
        .Array => |a| {
            _ = a;
            // comptime comptime_assert(
            //     a.len == 2 and a.child == u32,
            //     "Only accpeting [2]u32: got {d}[{any}]",
            //     .{ a.len, a.child },
            // );
            self.extra_data.appendAssumeCapacity(2);
            data_slice = &data;
        },
        else => {
            @compileError("Cannot add extra data of given type");
        },
    }
    self.extra_data.appendSliceAssumeCapacity(data_slice);
    return result;
}

pub fn parse(source: []const u8, allocator: std.mem.Allocator, expected_capacity: usize) !JSON {
    var nodes = std.MultiArrayList(JSON.Node){};
    try nodes.ensureTotalCapacity(allocator, expected_capacity);
    var scratch_space = try std.ArrayList(NodeIndex).initCapacity(allocator, @divExact(expected_capacity, 5));
    var parser = Parser{
        .allocator = allocator,
        .buffer = source,
        .string_map = JsonStringMap.init(allocator),
        .extra_data = try std.ArrayList(NodeIndex).initCapacity(allocator, expected_capacity),
    };
    var string_store = std.ArrayList(u8).init(allocator);
    try parser.push_state(.json_start);

    while (parser.stack_ptr != 0) {
        switch (parser.current_state()) {
            .json_start => {
                if (parser.index == 0) {
                    try nodes.append(allocator, Node{
                        .key = [_]NodeIndex{ 0, 0 },
                        .tag = .object,
                        .data = undefined,
                    });
                    try parser.push_state(.object_start);
                    try parser.push_state(.{ .expected_token = '{' });
                } else {
                    // We are here because we have finished all the parsing.
                    // const tag: u8 = @truncate(scratch_space[0]);
                    // std.debug.print("Scratch space: {d}\n", .{scratch_space.items});
                    const value: u64 = @bitCast(scratch_space.items[1..3].*);
                    nodes.items(.data)[0] = value;
                    _ = parser.pop_state();
                    break;
                }
            },
            .object_start => {
                _ = parser.pop_state();
                const start: u32 = @intCast(scratch_space.items.len);
                try parser.push_state(.{ .expected_token = '}' });
                try parser.push_state(.{ .object_end = start });
                try parser.push_state(.element_start);
            },
            .object_end => |s| {
                switch (parser.buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        parser.index += 1;
                        try parser.push_state(.padding);
                        continue;
                    },
                    ',' => {
                        parser.index += 1;
                        try parser.push_state(.element_start);
                        continue;
                    },
                    else => {},
                }

                _ = parser.pop_state();

                const elements = scratch_space.items[s..];
                const data_location: u64 = @intCast(try parser.add_extra(elements));

                scratch_space.shrinkRetainingCapacity(s);

                try scratch_space.append(@intFromEnum(Node.Tag.object));

                const data = @as([*]u32, @ptrCast(@constCast(&data_location)));
                try scratch_space.appendSlice(data[0..2]);
                // std.debug.print("Stack Trace: {any}\n", .{parser.state_stack[0..parser.stack_ptr]});
                // std.debug.print("Object written\n", .{});
            },
            .expected_token => |expected_char| {
                const current_char = parser.buffer[parser.index];
                switch (current_char) {
                    ' ', '\n', '\t', '\r' => {
                        parser.index += 1;
                        try parser.push_state(.padding);
                        continue;
                    },
                    else => {},
                }

                if (current_char == expected_char) {
                    parser.index += 1;
                    _ = parser.pop_state();
                } else {
                    std.log.err("Expected {c} but got {c}\n", .{ expected_char, current_char });
                    return ParserError.InvalidJSON;
                }
            },
            .element_start => {
                _ = parser.pop_state();
                const start: u32 = @intCast(scratch_space.items.len);
                try parser.push_state(.{ .element_end = start });
                try parser.push_state(.value);
                try parser.push_state(.{ .expected_token = ':' });
                try parser.push_state(.string);
            },
            .element_end => |s| {
                // std.debug.print("Element end\n", .{});
                const key: [2]NodeIndex = scratch_space.items[s + 1 ..][0..2].*;
                const tag: u8 = @truncate(scratch_space.items[s + 3]);
                const value: u64 = @bitCast(scratch_space.items[s + 4 ..][0..2].*);
                scratch_space.shrinkRetainingCapacity(s);

                const pos: u32 = @intCast(nodes.len);
                try nodes.append(allocator, Node{
                    .key = key,
                    .tag = @enumFromInt(tag),
                    .data = value,
                });

                try scratch_space.append(pos);
                _ = parser.pop_state();
            },
            .string => {
                switch (parser.buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        parser.index += 1;
                        try parser.push_state(.padding);
                        continue;
                    },
                    '"' => {
                        parser.index += 1;
                    },
                    else => {
                        // std.debug.print("Stack Trace: {any}\n", .{parser.state_stack[0..parser.stack_ptr]});
                        std.log.err("Expected \" but got {c}\n", .{parser.buffer[parser.index]});
                        return ParserError.InvalidJSON;
                    },
                }

                _ = parser.pop_state();

                const start_pos = parser.index;
                while (parser.buffer[parser.index] != '"') {
                    parser.index += 1;
                }
                const end_pos = parser.index;
                parser.index += 1;

                const string = parser.buffer[start_pos..end_pos];
                // std.debug.print("String value: {s}\n", .{string});
                const value = parser.string_map.get(string);
                var output: [2]NodeIndex = undefined;

                if (value) |v| {
                    output = v;
                } else {
                    const string_start: u32 = @intCast(string_store.items.len);
                    try string_store.appendSlice(string);
                    const string_end: u32 = @intCast(string_store.items.len);

                    const data_location = [2]u32{ string_start, string_end };

                    try parser.string_map.put(try allocator.dupe(u8, string_store.items[string_start..string_end]), data_location);

                    output = data_location;
                }
                try scratch_space.append(@intFromEnum(Node.Tag.string));
                try scratch_space.appendSlice(&output);
            },
            .array_start => {
                // std.debug.print("Array start\n", .{});
                const start: u32 = @intCast(scratch_space.items.len);
                try parser.push_state(.{ .array_end = start });
                try parser.push_state(.{ .array_mid = start });
                try parser.push_state(.value);
            },
            .array_mid => |scratch_len| {
                if (scratch_len != scratch_space.items.len) {
                    const tag: u8 = @truncate(scratch_space.items[scratch_len..][0]);
                    const value: u64 = @bitCast(scratch_space.items[scratch_len..][1..3].*);

                    scratch_space.shrinkRetainingCapacity(scratch_len);
                    const pos: u32 = @intCast(nodes.len);
                    try nodes.append(
                        allocator,
                        Node{ .key = [2]NodeIndex{ 0, 0 }, .tag = @enumFromInt(tag), .data = value },
                    );
                    try scratch_space.append(pos);
                    parser.state_stack[parser.stack_ptr - 1].array_mid += 1;
                }
                switch (parser.buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        parser.index += 1;
                        try parser.push_state(.padding);
                        continue;
                    },
                    ',' => {
                        parser.index += 1;
                        try parser.push_state(.value);
                        continue;
                    },
                    ']' => {
                        parser.index += 1;
                    },
                    else => {
                        std.log.err("Expected a ] but got {s}\n", .{parser.buffer[parser.index..]});
                        return ParserError.InvalidJSON;
                    },
                }
                _ = parser.pop_state();
            },
            .array_end => |s| {
                // std.debug.print("Array end\n", .{});

                _ = parser.pop_state();
                _ = parser.pop_state();

                const elements = scratch_space.items[s..];
                const data_location: u64 = @intCast(try parser.add_extra(elements));

                scratch_space.shrinkRetainingCapacity(s);

                try scratch_space.append(@intFromEnum(Node.Tag.array));
                const data = @as([*]u32, @ptrCast(@constCast(&data_location)));
                try scratch_space.appendSlice(data[0..2]);
                // std.debug.print("Stack Trace: {d} {any}\n", .{ parser.index, parser.state_stack[0..parser.stack_ptr] });
            },
            .padding => {
                while (true) {
                    switch (parser.buffer[parser.index]) {
                        ' ', '\n', '\t', '\r' => {
                            parser.index += 1;
                        },
                        else => {
                            _ = parser.pop_state();
                            break;
                        },
                    }
                }
            },
            .number => {
                // std.debug.print("Number\n", .{});
                var is_float = false;
                // std.debug.print("scratch: {d}\n", .{scratch_space.items});

                const start = parser.index;
                parser.index += 1;
                while (((parser.buffer[parser.index] >= '0' and parser.buffer[parser.index] <= '9') or parser.buffer[parser.index] == '.')) {
                    if (parser.buffer[parser.index] == '.') {
                        is_float = true;
                    }
                    parser.index += 1;
                }
                if ((parser.buffer[parser.index] == 'e' or parser.buffer[parser.index] == 'E')) {
                    parser.index += 1;
                    if ((parser.buffer[parser.index] == '+' or parser.buffer[parser.index] == '-')) {
                        parser.index += 1;
                    }
                    while ((parser.buffer[parser.index] >= '0' and parser.buffer[parser.index] <= '9')) {
                        parser.index += 1;
                    }
                }
                const end = parser.index;
                const value: f64 = std.fmt.parseFloat(f64, parser.buffer[start..end]) catch {
                    std.debug.print("Test: {s}\n", .{parser.buffer[parser.index..]});
                    std.log.err("Invalid number: {s}\n", .{parser.buffer[start..end]});
                    return ParserError.InvalidJSON;
                };
                _ = parser.pop_state();
                try scratch_space.append(@intFromEnum(Node.Tag.float));
                const value_arr: [*]u32 = @as([*]u32, @ptrCast(@constCast(&value)));
                try scratch_space.appendSlice(value_arr[0..2]);
                // std.debug.print("scratch: {d}\n", .{scratch_space.items});
            },
            .value => {
                switch (parser.buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        parser.index += 1;
                        try parser.push_state(.padding);
                    },
                    '{' => {
                        _ = parser.pop_state();
                        parser.index += 1;
                        try parser.push_state(.object_start);
                    },
                    '[' => {
                        _ = parser.pop_state();
                        parser.index += 1;
                        try parser.push_state(.array_start);
                    },
                    '"' => {
                        _ = parser.pop_state();
                        try parser.push_state(.string);
                    },
                    '-', '0'...'9' => {
                        _ = parser.pop_state();
                        try parser.push_state(.number);
                    },
                    'n' => {
                        _ = parser.pop_state();
                        try parser.push_state(.null);
                    },
                    't' => {
                        _ = parser.pop_state();
                        try parser.push_state(.true);
                    },
                    'f' => {
                        _ = parser.pop_state();
                        try parser.push_state(.false);
                    },
                    else => {
                        std.log.err("Expected a value but got {s}\n", .{parser.buffer[parser.index..]});
                        return ParserError.InvalidJSON;
                    },
                }
            },
            .null => {
                const keyword = "null";
                const start = parser.index;
                for (keyword) |k| {
                    if (parser.buffer[parser.index] == k) {
                        parser.index += 1;
                    } else {
                        std.log.err("Invalid keyword: {s}\n", .{parser.buffer[start..]});
                        return ParserError.InvalidJSON;
                    }
                }
                _ = parser.pop_state();
                const value: u64 = 0;
                try scratch_space.append(@intFromEnum(Node.Tag.null));
                const value_arr: [*]u32 = @as([*]u32, @ptrCast(@constCast(&value)));
                try scratch_space.appendSlice(value_arr[0..2]);
            },
            .true => {
                const keyword = "true";
                const start = parser.index;
                for (keyword) |k| {
                    if (parser.buffer[parser.index] == k) {
                        parser.index += 1;
                    } else {
                        std.log.err("Invalid keyword: {s}\n", .{parser.buffer[start..]});
                        return ParserError.InvalidJSON;
                    }
                }
                _ = parser.pop_state();
                const value: u64 = 1;
                try scratch_space.append(@intFromEnum(Node.Tag.boolean_true));
                const value_arr: [*]u32 = @as([*]u32, @ptrCast(@constCast(&value)));
                try scratch_space.appendSlice(value_arr[0..2]);
            },
            .false => {
                // std.debug.print("False\n", .{});
                const keyword = "false";
                const start = parser.index;
                for (keyword) |k| {
                    if (parser.buffer[parser.index] == k) {
                        parser.index += 1;
                    } else {
                        std.log.err("Invalid keyword: {s}\n", .{parser.buffer[start..]});
                        return ParserError.InvalidJSON;
                    }
                }
                _ = parser.pop_state();
                // std.debug.print("parser.index: {s}\n", .{parser.buffer[parser.index..]});
                const value: u64 = 0;
                try scratch_space.append(@intFromEnum(Node.Tag.boolean_false));
                const value_arr: [*]u32 = @as([*]u32, @ptrCast(@constCast(&value)));
                try scratch_space.appendSlice(value_arr[0..2]);
            },
            else => {
                std.log.err("Reached state: {any} {any}\n", .{ parser.stack_ptr, parser.current_state() });
                unreachable;
            },
        }
    }

    // std.debug.print(
    //     "Strings: {s}\n",
    //     .{string_store.items},
    // );
    //
    // for (0..nodes.len) |i| {
    //     std.debug.print(
    //         "Node[{d}]: {s}\n",
    //         .{ i, nodes.get(i) },
    //     );
    // }
    //
    // std.debug.print(
    //     "extra data: {d}\n",
    //     .{parser.extra_data.items},
    // );

    const json = JSON{
        .extra_data = try parser.extra_data.toOwnedSlice(),
        .strings = try string_store.toOwnedSlice(),
        .nodes = nodes.toOwnedSlice(),
        .allocator = allocator,
    };

    scratch_space.deinit();
    var key_iter = parser.string_map.keyIterator();
    while (key_iter.next()) |key| {
        allocator.free(key.*);
    }
    parser.string_map.deinit();

    return json;
}

// pub const Node = struct {
//     key: String,
//     tag: Tag,
//     data: Data,
//
//     pub const Value = struct {
//         tag: Tag,
//         data: Data,
//     };
//
//     pub const Data = u64;
//
//     pub const Float = f64;
//     pub const Object = []NodeIndex;
//     pub const Array = []NodeIndex;
//     pub const String = [2]NodeIndex;
//     pub const Boolean = bool;
//     pub const None = void;
//
//     pub const Tag = enum(u8) {
//         /// Extra data array stores [N + 1] elements where
//         /// N is the value at the index that the data points to
//         /// N, element1, ..., elementN
//         /// Value points to location of N
//         object,
//         /// bitcast value field to f64
//         number,
//         /// Extra data array stores start, end
//         /// Value points to the location of start
//         string,
//         /// Extra data array stores [N + 1] Values
//         /// N is the value at the index that data points to
//         /// N, value1, value2, ..., valueN
//         /// Value field points to location of N
//         array,
//         /// Stores nothing
//         boolean_true,
//         /// stores nothing
//         boolean_false,
//         /// data does not point to anything
//         null,
//     };
//
//     pub fn format(self: *const Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//         switch (self.tag) {
//             .number => {
//                 try writer.print(
//                     "Node{{" ++ "key:({d}, {d}), tag:{s}, data:{d}" ++ "}}",
//                     .{
//                         self.key[0],
//                         self.key[1],
//                         @tagName(self.tag),
//                         @as(f64, @bitCast(self.data)),
//                     },
//                 );
//             },
//             .string => {
//                 const data = @as([2]u32, @bitCast(self.data));
//                 try writer.print(
//                     "Node{{" ++ "key:({d}, {d}), tag:{s}, data:({d}, {d})" ++ "}}",
//                     .{
//                         self.key[0],
//                         self.key[1],
//                         @tagName(self.tag),
//                         data[0],
//                         data[1],
//                     },
//                 );
//             },
//             else => {
//                 try writer.print(
//                     "Node{{" ++ "key:({d}, {d}), tag:{s}, data:{d}" ++ "}}",
//                     .{
//                         self.key[0],
//                         self.key[1],
//                         @tagName(self.tag),
//                         self.data,
//                     },
//                 );
//             },
//         }
//     }
// };

test parse {
    var json = try parse(
        \\{
        \\ "test1" 
        \\      :["t", -1.2],
        \\   "test2" :
        \\      [1, "two", true, false ],
        \\   "test3" :
        \\      { "nested": [1, "two"] }
        // \\   "test4\" :
        // \\      [1, "two", true, false },
        \\}
    , std.testing.allocator, 10);
    defer json.deinit();
    std.debug.print("JSON: {s}\n", .{json});
}

const std = @import("std");
const JSON = @import("json.zig");
const Node = JSON.Node;
// const comptime_assert = @import("../assert.zig").comptime_assert;
//
