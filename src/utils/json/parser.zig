// pub const HaversineParser = @This();

pub const BUFFER_SIZE = 8192 * 2 * 2 * 2;
pub const INDEX_TYPE = u32;
pub const MAX_NODE_DATA = std.math.maxInt(INDEX_TYPE);

const Parser = @This();

// Supporting data for the parser
is_done: bool,
is_file: bool,
next_token: Token,
file: std.fs.File,
reader: BufferedReader,
lexer: Lexer,
buffer_pos: usize,
buffer: []u8,
scratch_space: std.ArrayListUnmanaged(NodeIndex),
string_map: JsonStringMap,
allocator: std.mem.Allocator,

// Actual data
string_store: std.ArrayList(u8),
nodes: JSON.NodeArray,
extra_data: JSON.DataArray,

pub const BufferedReader = std.io.BufferedReader(BUFFER_SIZE, std.fs.File.Reader);
pub const JsonStringMap = std.StringHashMap(Node.String);
pub const Error = error{InvalidToken};
pub const ParserError = Error || std.mem.Allocator.Error || Parser.BufferedReader.Error || std.fs.File.OpenError;

pub fn init(file_name: []const u8, allocator: std.mem.Allocator, expected_capacity: usize) !*Parser {
    var parser = try allocator.create(Parser);

    parser.file = try std.fs.cwd().openFile(file_name, .{});
    parser.reader = .{ .unbuffered_reader = undefined };
    parser.buffer_pos = 0;
    parser.is_done = false;
    parser.is_file = true;

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

    parser.string_map = JsonStringMap.init(allocator);

    return parser;
}

pub fn initSlice(slice: []u8, allocator: std.mem.Allocator, expected_capacity: usize) !*Parser {
    var parser = try allocator.create(Parser);
    parser.file = undefined;
    parser.reader = undefined;
    parser.is_done = false;
    parser.is_file = false;

    parser.buffer = slice;
    parser.buffer_pos = slice.len;

    parser.lexer = try Lexer.init(parser.buffer[0..parser.buffer_pos]);

    parser.next_token = parser.lexer.next_token();

    parser.scratch_space = .{};
    parser.nodes = .{};
    try parser.nodes.ensureTotalCapacity(allocator, expected_capacity);
    parser.string_store = std.ArrayList(u8).init(allocator);
    parser.extra_data = try std.ArrayList(NodeIndex).initCapacity(allocator, expected_capacity);
    parser.allocator = allocator;

    parser.string_map = JsonStringMap.init(allocator);

    return parser;
}

pub fn deinit(self: *Parser) void {
    var key_iter = self.string_map.keyIterator();
    while (key_iter.next()) |key| {
        self.allocator.free(key.*);
    }
    self.string_map.deinit();

    if (self.is_file) {
        self.file.close();
        self.allocator.free(self.buffer);
    }
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
            .key = [2]NodeIndex{ 0, 0 },
            .tag = .object,
            .data = undefined,
        },
    );

    self.nodes.items(.data)[0] = try self.parse_expect_object();
}

fn add_extra(self: *Parser, data: anytype) std.mem.Allocator.Error!JSON.NodeIndex {
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

// NOTE: This is the bottleneck
fn get_next_token(self: *Parser) !Token {
    // const p = tracer.trace(.json_token).start();
    // defer p.end();

    var current_token = self.next_token;

    if (self.is_file and current_token.tag == .EOF and !self.is_done) {
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

    return current_token;
}

fn parse_expect_object(self: *Parser) ParserError!NodeIndex {
    // const p = tracer.trace( .json_object).start();
    // defer p.end();
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
        std.debug.print("Got token: {s}\n", .{comma});
        return Error.InvalidToken;
    }
    const data_location = try self.add_extra(self.scratch_space.items[start..]);
    return data_location;
}

fn parse_expect_entry(self: *Parser) ParserError!NodeIndex {
    // const p = tracer.trace(.json_entry).start();
    // defer p.end();
    const key = try self.expect_consume_token(.STRING);
    const entry_key = try self.parse_exect_string_value(key);
    _ = try self.expect_consume_token(.COLON);

    // NOTE(aditya): The node is added before creating the value for it as
    // a small performance imporovement when querying the json as it is more
    // likely that when you are checking for the string keys matching the value
    // is in the cache already. This gave a small 5% improvemnet in speed.
    const pos = self.nodes.len;
    try self.nodes.append(
        self.allocator,
        JSON.Node{ .key = entry_key, .tag = undefined, .data = undefined },
    );

    const tag, const value = try self.parse_expect_value();

    const node_slice = self.nodes.slice();
    node_slice.items(.tag)[pos] = tag;
    node_slice.items(.data)[pos] = value;

    return @intCast(pos);
}

fn parse_exect_string_value(self: *Parser, key: Token) ParserError!Node.String {
    const string = self.buffer[key.start_pos..key.end_pos];
    const value = self.string_map.get(string);
    if (value) |v| {
        return v;
    }

    const string_start: u32 = @intCast(self.string_store.items.len);
    try self.string_store.appendSlice(string);
    const string_end: u32 = @intCast(self.string_store.items.len);

    const data_location = [2]u32{ string_start, string_end };

    try self.string_map.put(try self.allocator.dupe(u8, self.string_store.items[string_start..string_end]), data_location);

    return data_location;
}

fn parse_expect_value(self: *Parser) ParserError!struct { NodeTag, JSON.Node.Data } {
    const next_token = try self.get_next_token();

    switch (next_token.tag) {
        .LEFT_BRACKET => {
            const pos = try self.parse_expect_object();
            return .{ NodeTag.object, @as(u64, @intCast(pos)) };
        },
        .LEFT_BRACE => {
            const pos = try self.parse_expect_array_value();
            return .{ NodeTag.array, @as(u64, @intCast(pos)) };
        },
        .STRING => {
            const string = try self.parse_exect_string_value(next_token);
            return .{ NodeTag.string, @as(u64, @bitCast(string)) };
        },
        .NUMBER => {
            const value: f64 = std.fmt.parseFloat(f64, self.buffer[next_token.start_pos..next_token.end_pos]) catch {
                return Error.InvalidToken;
            };
            return .{ NodeTag.float, @as(u64, @bitCast(value)) };
        },
        .INTEGER => {
            const value: i64 = std.fmt.parseInt(i64, self.buffer[next_token.start_pos..next_token.end_pos], 10) catch {
                return Error.InvalidToken;
            };
            return .{ NodeTag.integer, @as(u64, @bitCast(value)) };
        },
        .TRUE => {
            return .{ NodeTag.boolean_true, 1 };
        },
        .FALSE => {
            return .{ NodeTag.boolean_false, 0 };
        },
        .NULL => {
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

fn parse_expect_array_value(self: *Parser) ParserError!NodeIndex {
    const start = self.scratch_space.items.len;
    defer self.scratch_space.shrinkRetainingCapacity(start);

    var comma: Token = undefined;
    while (true) {
        const pos: u32 = @intCast(self.nodes.len);
        try self.nodes.append(
            self.allocator,
            JSON.Node{ .key = [2]NodeIndex{ 0, 0 }, .tag = undefined, .data = undefined },
        );
        const tag, const value = try parse_expect_value(self);

        const node_slice = self.nodes.slice();
        node_slice.items(.tag)[pos] = tag;
        node_slice.items(.data)[pos] = value;

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
        return Error.InvalidToken;
    }
    return current_token;
}

const Lexer = @import("lexer.zig");
const JSON = @import("json.zig");
const tracer = @import("tracer");
const Node = JSON.Node;
const NodeTag = JSON.Node.Tag;
const NodeIndex = JSON.NodeIndex;
const Token = Lexer.Token;
const comptime_assert = @import("../assert.zig").comptime_assert;
const std = @import("std");
