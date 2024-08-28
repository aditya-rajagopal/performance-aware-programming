// pub const HaversineParser = @This();

pub const BUFFER_SIZE = 1024000;

const usage =
    \\ 
    \\ Usage:
    \\ haversine_parse [haversine data file *.json]
;

const JSONParser = struct {
    next_token: Token = undefined,
    file: std.fs.File = undefined,
    reader: BufferedReader = .{ .unbuffered_reader = undefined },
    lexer: JsonLexer = undefined,
    buffer_pos: usize = 0,
    is_done: bool = false,
};

const JSON = struct {
    string_store: std.ArrayList(u8),
    json_elements: std.MultiArrayList(JSONElement),
    extra_data: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    pub const root_node = 0;
    pub const StringPtr = ExtraDataIndex;
    pub const NodeIndex = usize;
    pub const ExtraDataIndex = usize;
    pub const ExtraData = struct { start: usize, end: usize };

    pub fn deinit(self: *JSON) void {
        // std.debug.print("JSON deinit\n", .{});
        self.string_store.deinit();
        self.extra_data.deinit();
        self.json_elements.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    const JSONValueTypes = enum {
        json,
        integer,
        float,
        string,
        array,
        boolean,
        none,
    };

    const JSONElement = struct {
        key: StringPtr,
        value: Payload,

        pub const Payload = union(JSONValueTypes) {
            json: ExtraDataIndex,
            integer: i64,
            float: f64,
            string: ExtraDataIndex,
            array: ExtraDataIndex,
            boolean: bool,
            none,
        };
    };
};

pub const BufferedReader = std.io.BufferedReader(BUFFER_SIZE, std.fs.File.Reader);

pub const Error = error{InvalidToken};
pub const ParserError = Error || std.mem.Allocator.Error || BufferedReader.Error || std.fs.File.OpenError;

var buffer: [BUFFER_SIZE]u8 = undefined;
var parser: JSONParser = undefined;
var is_initialized = false;
var scratch_space: std.ArrayListUnmanaged(usize) = undefined;
var string_map: std.StringHashMap(usize) = undefined;

pub fn parser_init(file_name: []const u8) !void {
    if (is_initialized) {
        return;
    }
    parser = JSONParser{};
    parser.file = try std.fs.cwd().openFile(file_name, .{});
    parser.reader.unbuffered_reader = parser.file.reader();
    parser.buffer_pos = try parser.reader.read(&buffer);

    parser.lexer = try JsonLexer.init(buffer[0..parser.buffer_pos]);

    parser.next_token = parser.lexer.next_token();

    scratch_space = .{};
    is_initialized = true;
    // std.debug.print("Parser is shutdown\n", .{});
}

pub fn parser_shutdown(allocator: std.mem.Allocator) void {
    if (!is_initialized) {
        return;
    }
    parser.file.close();
    scratch_space.deinit(allocator);
    // std.debug.print("Parser is shutdown\n", .{});
    is_initialized = false;
}

pub fn get_next_token() !Token {
    var current_token = parser.next_token;

    // std.debug.print("Token Initial: {s}, {s}\n", .{ current_token, buffer[current_token.start_pos..current_token.end_pos] });
    if (current_token.tag == .EOF and !parser.is_done) {
        if (parser.buffer_pos != parser.next_token.end_pos) {
            const len = parser.buffer_pos - parser.next_token.end_pos;
            const remaining = buffer[parser.next_token.end_pos .. parser.next_token.end_pos + len];
            @memcpy(buffer[0..len], remaining);
            parser.buffer_pos = try parser.reader.read(buffer[len..]) + len;
        } else {
            parser.buffer_pos = try parser.reader.read(&buffer);
        }
        if (parser.buffer_pos != 0) {
            parser.lexer = try JsonLexer.init(buffer[0..parser.buffer_pos]);
            current_token = parser.lexer.next_token();
            parser.next_token = parser.lexer.next_token();
        } else {
            parser.is_done = true;
        }
    } else {
        parser.next_token = parser.lexer.next_token();
    }

    // std.debug.print("Token gotten: {s}, {s}\n", .{ current_token, buffer[current_token.start_pos..current_token.end_pos] });
    return current_token;
}

pub fn parse_json(file_name: []const u8, allocator: std.mem.Allocator, expected_capacity: usize) ParserError!*JSON {
    try parser_init(file_name);

    string_map = std.StringHashMap(usize).init(allocator);

    var json = try allocator.create(JSON);
    json.json_elements = .{};
    try json.json_elements.ensureTotalCapacity(allocator, expected_capacity);
    json.string_store = std.ArrayList(u8).init(allocator);
    json.extra_data = try std.ArrayList(usize).initCapacity(allocator, expected_capacity);
    json.allocator = allocator;

    // fill in 0th element to act as null string
    try json.string_store.append(0);
    try json.extra_data.append(0);
    try json.extra_data.append(0);

    _ = try expect_consume_token(.LEFT_BRACKET);

    try json.json_elements.append(
        json.allocator,
        JSON.JSONElement{
            .key = 0,
            .value = .{ .json = try parse_expect_json_value(json) },
        },
    );

    var iterator = string_map.keyIterator();
    while (iterator.next()) |k| {
        std.debug.print("Key: {s}\n", .{k.*});
    }
    string_map.deinit();
    parser_shutdown(allocator);
    return json;
}

fn parse_expect_json_value(json: *JSON) ParserError!JSON.ExtraDataIndex {
    // std.debug.print("Parsing json dict\n", .{});
    // _ = try expect_consume_token(.LEFT_BRACKET);
    const start = scratch_space.items.len;
    defer scratch_space.shrinkRetainingCapacity(start);
    var comma: Token = undefined;
    while (true) {
        const value = try parse_expect_entry(json);
        try scratch_space.append(json.allocator, value);
        comma = try get_next_token();
        if (comma.tag != .COMMA) {
            break;
        }
    }

    if (comma.tag != .RIGHT_BRACKET) {
        return Error.InvalidToken;
    }
    const data_location = try append_extra_data(json, scratch_space.items[start..]);

    return data_location;
}

fn parse_expect_entry(json: *JSON) ParserError!usize {
    // std.debug.print("Parsing json pair\n", .{});
    const string_location = try parse_exect_string_value(json);
    _ = try expect_consume_token(.COLON);

    const pos = json.json_elements.len;
    // const value_token = try get_next_token();
    try json.json_elements.append(
        json.allocator,
        JSON.JSONElement{ .key = string_location, .value = try parse_expect_value(json) },
    );
    return pos;
}

fn parse_exect_string_value(json: *JSON) ParserError!JSON.ExtraDataIndex {
    // std.debug.print("Parsing json string\n", .{});
    const key = try expect_consume_token(.STRING);
    const string = buffer[key.start_pos..key.end_pos];
    const value = string_map.get(string);
    if (value) |v| {
        return v;
    }

    const string_start = json.string_store.items.len;
    try json.string_store.appendSlice(string);
    const string_end = json.string_store.items.len;
    const data_location = json.extra_data.items.len;

    try string_map.put(json.string_store.items[string_start..string_end], data_location);

    try json.extra_data.append(string_start);
    try json.extra_data.append(string_end);
    return data_location;
}

fn parse_expect_value(json: *JSON) ParserError!JSON.JSONElement.Payload {
    // std.debug.print("Parsing json value\n", .{});
    const next_token = try get_next_token();

    switch (next_token.tag) {
        .LEFT_BRACKET => {
            const pos = try parse_expect_json_value(json);
            return JSON.JSONElement.Payload{ .json = pos };
        },
        .LEFT_BRACE => {
            const pos = try parse_expect_array_value(json);
            return JSON.JSONElement.Payload{ .array = pos };
        },
        .STRING => {
            return JSON.JSONElement.Payload{ .string = try parse_exect_string_value(json) };
        },
        .NUMBER => {
            return JSON.JSONElement.Payload{ .float = try parse_exect_float_value(next_token) };
        },
        .INTEGER => {
            return JSON.JSONElement.Payload{ .integer = try parse_exect_int_value(next_token) };
        },
        .TRUE => {
            _ = try get_next_token();
            return JSON.JSONElement.Payload{ .boolean = true };
        },
        .FALSE => {
            _ = try get_next_token();
            return JSON.JSONElement.Payload{ .boolean = false };
        },
        .NULL => {
            _ = try get_next_token();
            return .none;
        },
        .EOF => {
            return parse_expect_value(json);
        },
        .RIGHT_BRACE, .RIGHT_BRACKET, .COLON, .COMMA, .ILLEGAL => {
            std.debug.print("Invalid Value token: {s}\n", .{next_token});
            return Error.InvalidToken;
        },
    }
}

fn parse_exect_float_value(float_token: Token) ParserError!f64 {
    // std.debug.print("Parsing json float\n", .{});
    // const float_token = try expect_consume_token(.NUMBER);
    const output = std.fmt.parseFloat(f64, buffer[float_token.start_pos..float_token.end_pos]) catch {
        return Error.InvalidToken;
    };
    return output;
}

fn parse_exect_int_value(int_token: Token) ParserError!i64 {
    // std.debug.print("Parsing json int\n", .{});
    // const int_token = try expect_consume_token(.INTEGER);
    const output = std.fmt.parseInt(i64, buffer[int_token.start_pos..int_token.end_pos], 10) catch {
        return Error.InvalidToken;
    };
    return output;
}

fn parse_expect_array_value(json: *JSON) ParserError!JSON.ExtraDataIndex {
    // std.debug.print("Parsing json array\n", .{});
    // _ = try expect_consume_token(.LEFT_BRACE);
    const start = scratch_space.items.len;
    defer scratch_space.shrinkRetainingCapacity(start);

    var comma: Token = undefined;
    while (true) {
        // const value_token = try get_next_token();
        const value = try parse_expect_value(json);
        const pos = json.json_elements.len;
        try json.json_elements.append(json.allocator, JSON.JSONElement{ .key = 0, .value = value });
        try scratch_space.append(json.allocator, pos);

        comma = try get_next_token();
        // std.debug.print("Comma?: {s}\n", .{comma});
        if (comma.tag != .COMMA) {
            break;
        }
        // _ = try get_next_token();
    }
    if (comma.tag != .RIGHT_BRACE) {
        return Error.InvalidToken;
    }
    // _ = try expect_consume_token(.RIGHT_BRACE);
    const data_location = try append_extra_data(json, scratch_space.items[start..]);

    return data_location;
}

fn append_extra_data(json: *JSON, data: []const usize) std.mem.Allocator.Error!usize {
    const output = json.extra_data.items.len;
    const end = data.len;
    try json.extra_data.append(end);
    try json.extra_data.appendSlice(data);
    return output;
}

fn expect_consume_token(tag: Token.Tag) ParserError!Token {
    const current_token = try get_next_token();
    if (current_token.tag != tag) {
        // std.debug.print("Unexpected token: {s} expected type {s}\n", .{ current_token, @tagName(tag) });
        // std.debug.print("Buffer: {s}\n", .{buffer});
        return Error.InvalidToken;
    }
    return current_token;
}

fn eat_token(tag: Token.Tag) void {
    if (parser.next_token.tag == tag) {
        _ = get_next_token();
    }
}

pub fn main() !void {
    var start = try std.time.Timer.start();
    var parts = try std.time.Timer.start();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(gpa_allocator);
    defer args.deinit();
    _ = args.next().?;

    const file_name = args.next() orelse {
        std.log.err("Missing argument [file]", .{});
        std.log.err("{s}\n", .{usage});
        return;
    };

    var file_parts = std.mem.splitScalar(u8, file_name, '_');
    _ = file_parts.next();
    const num_points_str = file_parts.next() orelse {
        std.log.err("File: {s} is not of the form data_<num_points>_distribtuion.json\n", .{file_name});
        return;
    };

    const num_points = std.fmt.parseInt(usize, num_points_str, 10) catch {
        std.log.err(
            "File: {s} is not of the form data_<num_points>_distribtuion.json. Num points is not an integer: {s}\n",
            .{ file_name, num_points_str },
        );
        return;
    };

    // _ = try allocator.alloc(u8, 10e9);
    // _ = arena.reset(.retain_capacity);

    var init_time: u64 = undefined;
    var finish_time: u64 = undefined;

    init_time = parts.lap();

    var json = try parse_json(file_name, allocator, 50 * num_points);
    std.debug.print(
        "JSON: strings: {d}, nodes: {d}, extra_data: {d}\n",
        .{ json.string_store.items.len, json.json_elements.len, json.extra_data.items.len },
    );
    std.debug.print(
        "JSON elements: {any}\n\n\n{any}\n\n",
        .{ json.json_elements.items(.key)[0..3], json.json_elements.items(.value)[0..3] },
    );
    json.deinit();
    finish_time = parts.read();
    const end = start.read();
    std.debug.print("Time to init: {s}\n", .{std.fmt.fmtDuration(init_time)});
    std.debug.print("Time to lex: {s}\n", .{std.fmt.fmtDuration(finish_time)});
    std.debug.print("Total: {s}\n", .{std.fmt.fmtDuration(end)});
}

test JSONParser {
    std.debug.print("Size of Token: {d}\n", .{@sizeOf(Token)});
    std.debug.print("Size of JSON: {d}\n", .{@sizeOf(JSON)});
    std.debug.print("Size of JsonElement: {d}\n", .{@sizeOf(JSON.JSONElement)});
    std.debug.print("Size of Parser: {d}\n", .{@sizeOf(JSONParser)});
}

const JsonLexer = @import("./json_lexer.zig");
const Token = JsonLexer.Token;
const defines = @import("defines.zig");
const PointPair = defines.PointPair;
const std = @import("std");
