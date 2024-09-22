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
buffer: []u8,
buffer_len: usize = 0,
state_stack: [1024]state = [_]state{.unkown} ** 1024,
extra_data: std.ArrayList(NodeIndex),

index: usize = 0,
read_head: usize = 0,
stack_ptr: usize = 0,

string_map: JsonStringMap,

pub const JsonStringMap = std.StringHashMap(JSON.Node.String);
pub const NodeIndex = u32;
pub const BufferedReader = std.io.BufferedReader(BUFFER_SIZE, std.fs.File.Reader);

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
    init_file,
    buffer_file,
    error_state,
    unkown,
};

const ParserError = error{ MaxDepth, InvalidJSON, BufferOverflow };

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
            comptime comptime_assert(
                i.bits == 64 and i.signedness == .signed,
                "Int written to extra data array must be i64 : got {d}bit {s} integer\n",
                .{ i.bits, @tagName(i.signedness) },
            );
            try self.extra_data.ensureUnusedCapacity(2);
            const ptr = @as([*]u32, @ptrCast(@constCast(&data)));
            data_slice = ptr[0..2];
        },
        .Float => |f| {
            comptime comptime_assert(
                f.bits == 64,
                "Float written to extra data array must be f64: got f{d}\n",
                .{f.bits},
            );
            try self.extra_data.ensureUnusedCapacity(2);
            var float_data: u64 = @bitCast(data);
            const ptr = @as([*]u32, @ptrCast(&float_data));
            data_slice = ptr[0..2];
        },
        .Pointer => |p| {
            comptime comptime_assert(
                p.size == .Slice and p.child == u32,
                "Pointers of type []u32 are allowed: got {s} of type {any}\n",
                .{ @tagName(p.size), p.child },
            );
            try self.extra_data.ensureUnusedCapacity(data.len + 1);
            self.extra_data.appendAssumeCapacity(@as(u32, @intCast(data.len)));
            data_slice = data;
        },
        .Array => |a| {
            comptime comptime_assert(
                a.len == 2 and a.child == u32,
                "Only accpeting [2]u32: got {d}[{any}]",
                .{ a.len, a.child },
            );
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

fn inc_index(self: *Parser, comptime mode: ParserConfig.Mode) !?void {
    _ = mode;
    self.index += 1;
    if (self.index >= self.buffer_len) {
        try self.push_state(.buffer_file);
        return null;
    }
}

pub const ParserConfig = struct {
    mode: Mode = .buffer,

    pub const Mode = enum {
        file,
        buffer,
    };
};

pub fn parse(source_or_file: []const u8, allocator: std.mem.Allocator, expected_capacity: usize, comptime config: ParserConfig) !JSON {
    var nodes = std.MultiArrayList(JSON.Node){};
    try nodes.ensureTotalCapacity(allocator, expected_capacity);
    var scratch_space = try std.ArrayList(NodeIndex).initCapacity(allocator, @divExact(expected_capacity, 1));
    var parser = Parser{
        .allocator = allocator,
        .buffer = undefined,
        .string_map = JsonStringMap.init(allocator),
        .extra_data = try std.ArrayList(NodeIndex).initCapacity(allocator, expected_capacity),
    };

    var buffer: if (config.mode == .buffer) []const u8 else []u8 = undefined;
    if (config.mode == .buffer) {
        buffer = source_or_file;
    } else {
        buffer = (try allocator.alloc(u8, BUFFER_SIZE));
    }
    var temp_buffer: []u8 = undefined;
    if (config.mode == .file) {
        temp_buffer = (try allocator.alloc(u8, BUFFER_SIZE));
    }

    if (config.mode == .buffer) {
        parser.buffer_len = source_or_file.len;
    }

    var buffered_reader: if (config.mode == .buffer) void else BufferedReader = comptime blk: {
        if (config.mode == .buffer) {
            break :blk undefined;
        } else {
            const reader: BufferedReader = .{ .unbuffered_reader = undefined };

            break :blk reader;
        }
    };

    var string_store = std.ArrayList(u8).init(allocator);
    try parser.push_state(.json_start);
    var json_init: bool = true;
    outter: while (parser.stack_ptr != 0) {
        switch (parser.current_state()) {
            .init_file => {
                if (config.mode != .buffer) {
                    const file = try std.fs.cwd().openFile(source_or_file, .{});
                    buffered_reader.unbuffered_reader = file.reader();
                    parser.buffer_len = try buffered_reader.read(buffer);
                    _ = parser.pop_state();
                    // std.debug.print("Data: {s}\n\n", .{buffer[0..parser.buffer_len]});
                }
            },
            .buffer_file => {
                var p = tracer.trace(.json_parse_read_file, BUFFER_SIZE).start();
                if (config.mode != .buffer) {
                    if (parser.buffer_len != parser.read_head) {
                        const len = parser.buffer_len - parser.read_head;
                        const remaining = buffer[parser.read_head..parser.buffer_len];
                        @memcpy(temp_buffer[0..len], remaining);
                        @memcpy(buffer[0..len], temp_buffer[0..len]);
                        // @memcpy(buffer[0..len], remaining);
                        parser.buffer_len = try buffered_reader.read(buffer[len..]) + len;
                    } else {
                        parser.buffer_len = try buffered_reader.read(buffer);
                    }
                    parser.index = 0;
                    parser.read_head = 0;
                }
                _ = parser.pop_state();
                p.end();
            },
            .json_start => {
                if (json_init) {
                    json_init = false;
                    try nodes.append(allocator, Node{
                        .key = [_]NodeIndex{ 0, 0 },
                        .tag = .object,
                        .data = undefined,
                    });
                    try parser.push_state(.object_start);
                    try parser.push_state(.{ .expected_token = '{' });
                    if (config.mode == .file) {
                        try parser.push_state(.init_file);
                    }
                } else {
                    // We are here because we have finished all the parsing.
                    // const tag: u8 = @truncate(scratch_space[0]);
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
                switch (buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        try parser.push_state(.padding);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                        continue;
                    },
                    ',' => {
                        try parser.push_state(.element_start);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
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
            },
            .expected_token => |expected_char| {
                const current_char = buffer[parser.index];
                switch (current_char) {
                    ' ', '\n', '\t', '\r' => {
                        try parser.push_state(.padding);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                        continue;
                    },
                    else => {},
                }

                if (current_char == expected_char) {
                    _ = parser.pop_state();
                    parser.read_head += 1;
                    try parser.inc_index(config.mode) orelse continue :outter;
                } else {
                    std.log.err("Data: {s}\n", .{buffer[parser.index..]});
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
                const tag: Node.Tag = @enumFromInt(scratch_space.items[s + 3]);
                const value: u64 = @bitCast(scratch_space.items[s + 4 ..][0..2].*);
                scratch_space.shrinkRetainingCapacity(s);

                const pos: u32 = @intCast(nodes.len);
                try nodes.append(allocator, Node{
                    .key = key,
                    .tag = tag,
                    .data = value,
                });

                try scratch_space.append(pos);
                _ = parser.pop_state();
            },
            .string => {
                // std.debug.print("Stack Trace: {any}\n", .{parser.state_stack[0..parser.stack_ptr]});
                // std.debug.print("String start: {s}\n", .{buffer[parser.index..]});

                // if (buffer[parser.index] == ' ' or buffer[parser.index] == '\n' or buffer[parser.index] == '\t' or buffer[parser.index] == '\r') {
                //     try parser.push_state(.padding);
                //     parser.read_head += 1;
                //     try parser.inc_index(config.mode) orelse continue :outter;
                //     continue;
                // } else if (buffer[parser.index] == '"') {
                //     try parser.inc_index(config.mode) orelse continue :outter;
                // } else {
                //     std.log.err("Data: {s}\n", .{buffer[parser.index..]});
                //     std.log.err("Expected \" but got {c}\n", .{buffer[parser.index]});
                //     return ParserError.InvalidJSON;
                // }
                switch (buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        // std.debug.print("S: Found padding\n", .{});
                        try parser.push_state(.padding);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                        continue;
                    },
                    '"' => {
                        try parser.inc_index(config.mode) orelse continue :outter;
                    },
                    else => {
                        // std.debug.print("Stack Trace: {any}\n", .{parser.state_stack[0..parser.stack_ptr]});
                        std.log.err("Data: {s}\n", .{buffer[parser.index..]});
                        std.log.err("Expected \" but got {c}\n", .{buffer[parser.index]});
                        return ParserError.InvalidJSON;
                    },
                }
                // std.debug.print("String Actually start: {s}\n", .{buffer[parser.index..]});

                const start_pos = parser.index;
                while (buffer[parser.index] != '"') {
                    try parser.inc_index(config.mode) orelse continue :outter;
                }
                const end_pos = parser.index;
                // This might be a problem

                const string = buffer[start_pos..end_pos];
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

                _ = parser.pop_state();
                parser.read_head = parser.index + 1;
                try parser.inc_index(config.mode) orelse continue :outter;
            },
            .array_start => {
                // std.debug.print("Array start\n", .{});
                _ = parser.pop_state();
                const start: u32 = @intCast(scratch_space.items.len);
                try parser.push_state(.{ .array_end = start });
                try parser.push_state(.{ .array_mid = start });
                try parser.push_state(.value);
            },
            .array_mid => |scratch_len| {
                if (scratch_len != scratch_space.items.len) {
                    const tag: Node.Tag = @enumFromInt(scratch_space.items[scratch_len..][0]);
                    const value: u64 = @bitCast(scratch_space.items[scratch_len..][1..3].*);

                    scratch_space.shrinkRetainingCapacity(scratch_len);
                    const pos: u32 = @intCast(nodes.len);
                    try nodes.append(
                        allocator,
                        Node{ .key = [2]NodeIndex{ 0, 0 }, .tag = tag, .data = value },
                    );
                    try scratch_space.append(pos);
                    parser.state_stack[parser.stack_ptr - 1].array_mid += 1;
                }
                switch (buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        try parser.push_state(.padding);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                        continue;
                    },
                    ',' => {
                        // std.debug.print("Next array element\n", .{});
                        try parser.push_state(.value);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                        continue;
                    },
                    ']' => {
                        parser.read_head += 1;
                        _ = parser.pop_state();
                        try parser.inc_index(config.mode) orelse continue :outter;
                    },
                    else => {
                        std.log.err("Expected a ] but got {s}\n", .{buffer[parser.index..]});
                        return ParserError.InvalidJSON;
                    },
                }
            },
            .array_end => |s| {
                // std.debug.print("Array end\n", .{});

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
                    switch (buffer[parser.index]) {
                        ' ', '\n', '\t', '\r' => {
                            parser.read_head += 1;
                            try parser.inc_index(config.mode) orelse continue :outter;
                        },
                        else => {
                            _ = parser.pop_state();
                            break;
                        },
                    }
                }
            },
            .number => {
                switch (buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        try parser.push_state(.padding);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                        continue;
                    },
                    else => {},
                }
                // std.debug.print("Number\n", .{});
                var is_float = false;
                // std.debug.print("scratch: {d}\n", .{scratch_space.items});

                const start = parser.index;
                try parser.inc_index(config.mode) orelse continue :outter;
                while (((buffer[parser.index] >= '0' and buffer[parser.index] <= '9') or buffer[parser.index] == '.')) {
                    if (buffer[parser.index] == '.') {
                        is_float = true;
                    }
                    try parser.inc_index(config.mode) orelse continue :outter;
                }
                if ((buffer[parser.index] == 'e' or buffer[parser.index] == 'E')) {
                    try parser.inc_index(config.mode) orelse continue :outter;
                    if ((buffer[parser.index] == '+' or buffer[parser.index] == '-')) {
                        try parser.inc_index(config.mode) orelse continue :outter;
                    }
                    while ((buffer[parser.index] >= '0' and buffer[parser.index] <= '9')) {
                        try parser.inc_index(config.mode) orelse continue :outter;
                    }
                }
                const end = parser.index;
                parser.read_head = parser.index;

                const value: f64 = std.fmt.parseFloat(f64, buffer[start..end]) catch {
                    // std.debug.print("Test: {s}\n", .{buffer[parser.index..parser.buffer_len]});
                    std.log.err("Index: {d}\n", .{parser.index});
                    std.log.err("Invalid number: {s}\n", .{buffer[start..end]});
                    return ParserError.InvalidJSON;
                };
                _ = parser.pop_state();
                try scratch_space.append(@intFromEnum(Node.Tag.float));
                const value_arr: [*]u32 = @as([*]u32, @ptrCast(@constCast(&value)));
                try scratch_space.appendSlice(value_arr[0..2]);
                // std.debug.print("scratch: {d}\n", .{scratch_space.items});
            },
            .value => {
                // std.debug.print("Value: {d} {s}\n", .{ parser.index, buffer[parser.index..] });
                switch (buffer[parser.index]) {
                    ' ', '\n', '\t', '\r' => {
                        try parser.push_state(.padding);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                    },
                    '{' => {
                        _ = parser.pop_state();
                        try parser.push_state(.object_start);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
                    },
                    '[' => {
                        // std.debug.print("Found array\n", .{});
                        _ = parser.pop_state();
                        try parser.push_state(.array_start);
                        parser.read_head += 1;
                        try parser.inc_index(config.mode) orelse continue :outter;
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
                        std.log.err("Expected a value but got {s}\n", .{buffer[parser.index..]});
                        return ParserError.InvalidJSON;
                    },
                }
            },
            .null => {
                const keyword = "null";
                const start = parser.index;
                for (keyword) |k| {
                    if (buffer[parser.index] == k) {
                        try parser.inc_index(config.mode) orelse continue :outter;
                    } else {
                        std.log.err("Invalid keyword: {s}\n", .{buffer[start..]});
                        return ParserError.InvalidJSON;
                    }
                }
                parser.read_head = parser.index;
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
                    if (buffer[parser.index] == k) {
                        try parser.inc_index(config.mode) orelse continue :outter;
                    } else {
                        std.log.err("Invalid keyword: {s}\n", .{buffer[start..]});
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
                    if (buffer[parser.index] == k) {
                        try parser.inc_index(config.mode) orelse continue :outter;
                    } else {
                        std.log.err("Invalid keyword: {s}\n", .{buffer[start..]});
                        return ParserError.InvalidJSON;
                    }
                }
                _ = parser.pop_state();
                // std.debug.print("parser.index: {s}\n", .{buffer[parser.index..]});
                const value: u64 = 0;
                try scratch_space.append(@intFromEnum(Node.Tag.boolean_false));
                const value_arr: [*]u32 = @as([*]u32, @ptrCast(@constCast(&value)));
                try scratch_space.appendSlice(value_arr[0..2]);
            },
            .error_state => {
                std.log.err("Invalid JSON", .{});
                return ParserError.InvalidJSON;
            },
            else => {
                std.log.err("Reached state: {any} {any}\n", .{ parser.stack_ptr, parser.current_state() });
                unreachable;
            },
        }
    }

    const json = JSON{
        .extra_data = try parser.extra_data.toOwnedSlice(),
        .strings = try string_store.toOwnedSlice(),
        .nodes = nodes.toOwnedSlice(),
        .allocator = allocator,
    };
    if (config.mode == .file) {
        allocator.free(buffer);
        allocator.free(temp_buffer);
    }

    scratch_space.deinit();
    var key_iter = parser.string_map.keyIterator();
    while (key_iter.next()) |key| {
        allocator.free(key.*);
    }
    parser.string_map.deinit();

    return json;
}

// test parse {
//     var json = try parse(
//         \\{
//         \\ "test1"
//         \\      :["t", -1.2],
//         \\   "test2" :
//         \\      [1, "two", true, false ],
//         \\   "test3" :
//         \\      { "nested": [1, "two"] }
//         // \\   "test4\" :
//         // \\      [1, "two", true, false },
//         \\}
//     , std.testing.allocator, 10, .{});
//     std.debug.print("JSON: {s}\n", .{json});
//     json.deinit();
//     // json = try parse("data_10000000_clustered.json", std.testing.allocator, 10, .{ .mode = .file });
//     json = try parse("data_10_clustered.json", std.testing.allocator, 10, .{ .mode = .file });
//     defer json.deinit();
//     std.debug.print("JSON: {s}\n", .{json});
// }

const std = @import("std");
const JSON = @import("json.zig");
const Node = JSON.Node;
const tracer = @import("perf").tracer;
const comptime_assert = @import("../assert.zig").comptime_assert;
//
