// pub const HaversineParser = @This();

pub const BUFFER_SIZE = 1024000;
pub const INDEX_TYPE = u32;
pub const MAX_NODE_DATA = std.math.maxInt(INDEX_TYPE);

const Parser = @This();
next_token: Token,
file: std.fs.File,
reader: BufferedReader,
lexer: Lexer,
buffer_pos: usize,
is_done: bool,
buffer: []u8,
scratch_space: std.ArrayListUnmanaged(NodeIndex),
string_map: std.StringHashMap(NodeIndex),

string_store: std.ArrayList(u8),
nodes: JSON.NodeArray,
extra_data: JSON.DataArray,
allocator: std.mem.Allocator,

pub const BufferedReader = std.io.BufferedReader(BUFFER_SIZE, std.fs.File.Reader);

pub const Error = error{InvalidToken};
pub const ParserError = Error || std.mem.Allocator.Error || Parser.BufferedReader.Error || std.fs.File.OpenError;

pub fn init(file_name: []const u8, allocator: std.mem.Allocator, expected_capacity: usize) !*Parser {
    var parser = try allocator.create(Parser);
    parser.file = try std.fs.cwd().openFile(file_name, .{});
    parser.reader = .{ .unbuffered_reader = undefined };
    parser.buffer_pos = 0;
    parser.is_done = false;

    parser.reader.unbuffered_reader = parser.file.reader();
    parser.buffer = try allocator.alloc(u8, BUFFER_SIZE);
    parser.buffer_pos = try parser.reader.read(parser.*.buffer);

    parser.lexer = try Lexer.init(parser.buffer[0..parser.buffer_pos]);

    parser.next_token = parser.lexer.next_token();

    parser.scratch_space = .{};
    parser.nodes = .{};
    try parser.nodes.ensureTotalCapacity(allocator, expected_capacity);
    parser.string_store = std.ArrayList(u8).init(allocator);
    parser.extra_data = try std.ArrayList(NodeIndex).initCapacity(allocator, expected_capacity);
    parser.allocator = allocator;

    parser.string_map = std.StringHashMap(NodeIndex).init(allocator);

    return parser;
}

pub fn deinit(self: *Parser) void {
    var key_iter = self.string_map.keyIterator();
    while (key_iter.next()) |key| {
        self.allocator.free(key.*);
    }
    self.string_map.deinit();

    self.file.close();
    self.allocator.free(self.buffer);
    self.scratch_space.deinit(self.allocator);
    self.string_store.deinit();
    self.extra_data.deinit();
    self.nodes.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn parse(self: *Parser) ParserError!void {
    _ = try self.expect_consume_token(.LEFT_BRACKET);

    try self.nodes.append(
        self.allocator,
        JSON.Node{
            .key = 0,
            .tag = .json,
            .data = undefined,
        },
    );

    self.nodes.items(.data)[0] = try self.parse_expect_json_value();
}

fn add_extra(self: *Parser, data: anytype) std.mem.Allocator.Error!JSON.NodeIndex {
    // std.debug.print("Addign extra data: {any}\n", .{data});
    const typeinfo = @typeInfo(@TypeOf(data));
    var data_slice: []const u32 = undefined;

    const result = @as(u32, @intCast(self.extra_data.items.len));

    // @compileLog(typeinfo);

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
            // std.debug.print("DATA: {d}\n", .{ptr[0..2]});
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

pub fn get_next_token(self: *Parser) !Token {
    var current_token = self.next_token;

    // std.debug.print("Token Initial: {s}, {s}\n", .{ current_token, buffer[current_token.start_pos..current_token.end_pos] });
    if (current_token.tag == .EOF and !self.is_done) {
        if (self.buffer_pos != self.next_token.end_pos) {
            const len = self.buffer_pos - self.next_token.end_pos;
            const remaining = self.buffer[self.next_token.end_pos .. self.next_token.end_pos + len];
            @memcpy(self.buffer[0..len], remaining);
            self.buffer_pos = try self.reader.read(self.buffer[len..]) + len;
        } else {
            self.buffer_pos = try self.reader.read(self.buffer);
        }
        if (self.buffer_pos != 0) {
            self.lexer = try Lexer.init(self.buffer[0..self.buffer_pos]);
            current_token = self.lexer.next_token();
            self.next_token = self.lexer.next_token();
        } else {
            self.is_done = true;
        }
    } else {
        self.next_token = self.lexer.next_token();
    }

    // std.debug.print("Token gotten: {s}, {s}\n", .{ current_token, buffer[current_token.start_pos..current_token.end_pos] });
    return current_token;
}

fn parse_expect_json_value(self: *Parser) ParserError!NodeIndex {
    // std.debug.print("Parsing json dict\n", .{});
    // _ = try expect_consume_token(.LEFT_BRACKET);
    const start = self.scratch_space.items.len;
    defer self.scratch_space.shrinkRetainingCapacity(start);

    var comma: Token = undefined;
    while (true) {
        const value = try self.parse_expect_entry();
        try self.scratch_space.append(self.allocator, value);
        comma = try self.get_next_token();
        if (comma.tag != .COMMA) {
            break;
        }
    }

    if (comma.tag != .RIGHT_BRACKET) {
        return Error.InvalidToken;
    }
    const data_location = try self.add_extra(self.scratch_space.items[start..]);
    return data_location;
}

fn parse_expect_entry(self: *Parser) ParserError!NodeIndex {
    // std.debug.print("Parsing json pair\n", .{});
    const string_location = try self.parse_exect_string_value();
    _ = try self.expect_consume_token(.COLON);

    const pos = self.nodes.len;
    const tag, const value = try self.parse_expect_value();
    try self.nodes.append(
        self.allocator,
        JSON.Node{ .key = string_location, .tag = tag, .data = value },
    );
    return @intCast(pos);
}

fn parse_exect_string_value(self: *Parser) ParserError!NodeIndex {
    // std.debug.print("Parsing json string\n", .{});
    const key = try self.expect_consume_token(.STRING);
    const string = self.buffer[key.start_pos..key.end_pos];
    const value = self.string_map.get(string);
    if (value) |v| {
        return v;
    }

    const string_start: u32 = @intCast(self.string_store.items.len);
    try self.string_store.appendSlice(string);
    const string_end: u32 = @intCast(self.string_store.items.len);

    const data_location = try self.add_extra([_]u32{ string_start, string_end });

    try self.string_map.put(try self.allocator.dupe(u8, self.string_store.items[string_start..string_end]), data_location);

    return data_location;
}

fn parse_expect_value(self: *Parser) ParserError!struct { NodeTag, JSON.Node.Data } {
    // std.debug.print("Parsing json value\n", .{});
    const next_token = try self.get_next_token();

    switch (next_token.tag) {
        .LEFT_BRACKET => {
            const pos = try self.parse_expect_json_value();
            return .{ NodeTag.json, @as(u64, @intCast(pos)) };
        },
        .LEFT_BRACE => {
            const pos = try self.parse_expect_array_value();
            return .{ NodeTag.array, @as(u64, @intCast(pos)) };
        },
        .STRING => {
            const pos = try self.parse_exect_string_value();
            return .{ NodeTag.string, @as(u64, @intCast(pos)) };
        },
        .NUMBER => {
            const value: f64 = try self.parse_exect_float_value(next_token);
            return .{ NodeTag.float, @as(u64, @bitCast(value)) };
        },
        .INTEGER => {
            const value: i64 = try self.parse_exect_int_value(next_token);
            return .{ NodeTag.integer, @as(u64, @bitCast(value)) };
        },
        .TRUE => {
            _ = try self.get_next_token();
            return .{ NodeTag.boolean_true, 0 };
        },
        .FALSE => {
            _ = try self.get_next_token();
            return .{ NodeTag.boolean_false, 0 };
        },
        .NULL => {
            _ = try self.get_next_token();
            return .{ NodeTag.null, 0 };
        },
        .EOF => {
            return self.parse_expect_value();
        },
        .RIGHT_BRACE, .RIGHT_BRACKET, .COLON, .COMMA, .ILLEGAL => {
            std.debug.print("Invalid Value token: {s}\n", .{next_token});
            return Error.InvalidToken;
        },
    }
}

fn parse_exect_float_value(self: *Parser, float_token: Token) ParserError!f64 {
    // std.debug.print("Parsing json float\n", .{});
    // const float_token = try expect_consume_token(.NUMBER);
    const output = std.fmt.parseFloat(f64, self.buffer[float_token.start_pos..float_token.end_pos]) catch {
        return Error.InvalidToken;
    };
    return output;
}

fn parse_exect_int_value(self: *Parser, int_token: Token) ParserError!i64 {
    // std.debug.print("Parsing json int\n", .{});
    // const int_token = try expect_consume_token(.INTEGER);
    const output = std.fmt.parseInt(i64, self.buffer[int_token.start_pos..int_token.end_pos], 10) catch {
        return Error.InvalidToken;
    };
    return output;
}

fn parse_expect_array_value(self: *Parser) ParserError!NodeIndex {
    // std.debug.print("Parsing json array\n", .{});
    // _ = try expect_consume_token(.LEFT_BRACE);
    const start = self.scratch_space.items.len;
    defer self.scratch_space.shrinkRetainingCapacity(start);

    var comma: Token = undefined;
    while (true) {
        // const value_token = try get_next_token();
        const tag, const value = try parse_expect_value(self);
        const pos: u32 = @intCast(self.nodes.len);
        try self.nodes.append(
            self.allocator,
            JSON.Node{ .key = 0, .tag = tag, .data = value },
        );
        try self.scratch_space.append(self.allocator, pos);

        comma = try self.get_next_token();
        if (comma.tag != .COMMA) {
            break;
        }
    }
    if (comma.tag != .RIGHT_BRACE) {
        return Error.InvalidToken;
    }
    const data_location = try self.add_extra(self.scratch_space.items[start..]);

    return data_location;
}

fn expect_consume_token(self: *Parser, tag: Token.Tag) ParserError!Token {
    const current_token = try self.get_next_token();
    if (current_token.tag != tag) {
        // std.debug.print("Unexpected token: {s} expected type {s}\n", .{ current_token, @tagName(tag) });
        // std.debug.print("Buffer: {s}\n", .{buffer});
        return Error.InvalidToken;
    }
    return current_token;
}

fn eat_token(self: *Parser, tag: Token.Tag) void {
    if (self.next_token.tag == tag) {
        _ = get_next_token();
    }
}

test Parser {
    std.debug.print("Size of Token: {d}\n", .{@sizeOf(Token)});
    std.debug.print("Size of JSON: {d}\n", .{@sizeOf(JSON)});
    std.debug.print("Size of JsonElement: {d}\n", .{@sizeOf(JSON.Node)});
    std.debug.print("Size of Parser: {d}\n", .{@sizeOf(Parser)});
}

test JSON {
    // std.debug.print("{any}\n", .{@typeInfo([2]u32)});
    // var extra_data = std.ArrayList(u32).init(std.testing.allocator);
    // defer extra_data.deinit();
    //
    // const test_int: i64 = -1;
    // const test_float: f64 = std.math.pi;
    //
    // const slice_test: []const u32 align(8) = &[_]u32{ 1, 2 };
    // std.debug.print("Slice?: {any}\n", .{@TypeOf(slice_test[0..2].*)});
    //
    // var output = try add_extra(&extra_data, test_float);
    // std.debug.print("float output[{d}]: {d}\n", .{ output, extra_data.items });
    // var float_readback = try read_extra(extra_data.items, f64, output);
    // std.debug.print("Data read back: {d}\n", .{float_readback});
    //
    // output = try add_extra(&extra_data, slice_test);
    // std.debug.print("Slice output[{d}]: {d}\n", .{ output, extra_data.items });
    // const slice_readback = try read_extra(extra_data.items, []u32, output);
    // std.debug.print("Data read back: {d}\n", .{slice_readback});
    //
    // output = try add_extra(&extra_data, test_int);
    // std.debug.print("Output[{d}]: {d}\n", .{ output, extra_data.items });
    // const readback = try read_extra(extra_data.items, i64, output);
    // std.debug.print("Data read back: {d}\n", .{readback});
    //
    // output = try add_extra(&extra_data, test_float);
    // std.debug.print("float output[{d}]: {d}\n", .{ output, extra_data.items });
    // float_readback = try read_extra(extra_data.items, f64, output);
    // std.debug.print("Data read back: {d}\n", .{float_readback});
}

const Lexer = @import("lexer.zig");
const JSON = @import("json.zig");
const NodeTag = JSON.Node.Tag;
const NodeIndex = JSON.NodeIndex;
const Token = Lexer.Token;
const comptime_assert = @import("../assert.zig").comptime_assert;
const std = @import("std");
