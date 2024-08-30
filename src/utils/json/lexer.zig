pub const JsonLexer = @This();

source: []const u8,
current_pos: usize = 0,

pub const Token = struct {
    tag: Tag,
    start_pos: usize = 0,
    end_pos: usize = 0,

    pub const Tag = enum(u8) {
        LEFT_BRACE,
        RIGHT_BRACE,
        LEFT_BRACKET,
        RIGHT_BRACKET,
        STRING,
        NUMBER,
        INTEGER,
        COLON,
        COMMA,
        EOF,
        ILLEGAL,
        TRUE,
        FALSE,
        NULL,
    };

    pub fn format(self: Token, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        _ = try writer.print("Token{{ {s}: ({d}, {d}) }}", .{ @tagName(self.tag), self.start_pos, self.end_pos });
    }
};

const Keywords = std.ComptimeStringMap(
    Token.Tag,
    .{
        .{ "null", .NULL },
        .{ "true", .TRUE },
        .{ "false", .FALSE },
    },
);

pub const Error = error{ UNEXPECTED_EOF, InvalidFloat };

pub fn init(source: []const u8) !JsonLexer {
    return .{
        .source = source,
    };
}

pub fn next_token(self: *JsonLexer) Token {
    const pos = self.eat_till_valid() catch {
        return .{ .tag = .EOF, .start_pos = 0, .end_pos = self.source.len };
    };

    switch (self.source[pos]) {
        '{' => return .{ .tag = .LEFT_BRACKET, .start_pos = pos, .end_pos = pos + 1 },
        '}' => return .{ .tag = .RIGHT_BRACKET, .start_pos = pos, .end_pos = pos + 1 },
        '[' => return .{ .tag = .LEFT_BRACE, .start_pos = pos, .end_pos = pos + 1 },
        ']' => return .{ .tag = .RIGHT_BRACE, .start_pos = pos, .end_pos = pos + 1 },
        ',' => return .{ .tag = .COMMA, .start_pos = pos, .end_pos = pos + 1 },
        ':' => return .{ .tag = .COLON, .start_pos = pos, .end_pos = pos + 1 },
        '\"' => {
            const end = self.eat_till_scalar('\"') catch {
                return .{ .tag = .EOF, .start_pos = 0, .end_pos = pos };
            };
            return .{ .tag = .STRING, .start_pos = pos + 1, .end_pos = end };
        },
        '-', '0'...'9' => {
            const is_float = self.eat_number() catch {
                return .{ .tag = .EOF, .start_pos = 0, .end_pos = pos };
            };

            if (is_float) {
                return .{ .tag = .NUMBER, .start_pos = pos, .end_pos = self.current_pos };
            } else {
                return .{ .tag = .INTEGER, .start_pos = pos, .end_pos = self.current_pos };
            }
        },
        else => {
            const end = self.eat_till_delimiter() catch {
                return .{ .tag = .EOF, .start_pos = 0, .end_pos = pos };
            };

            const keyword = self.source[pos..end];
            const TokenTag = Keywords.get(keyword);
            if (TokenTag) |tag| {
                return .{ .tag = tag, .start_pos = pos, .end_pos = end };
            } else {
                // assert(false, "Illegal keyword: {s}\n", .{keyword});
                return .{ .tag = .ILLEGAL, .start_pos = pos, .end_pos = end };
            }
        },
    }
}

// TODO(aditya): Possible performance bottleneck
fn eat_number(self: *JsonLexer) !bool {
    var pos = try self.increment_pos();
    var char = self.source[pos];
    var is_float = false;
    while ((char >= '0' and char <= '9') or char == '.') {
        if (char == '.') {
            is_float = true;
        }
        pos = try self.increment_pos();
        char = self.source[pos];
    }
    if (char == 'e' or char == 'E') {
        pos = try self.increment_pos();
        char = self.source[pos];
        if (char == '+' or char == '-') {
            pos = try self.increment_pos();
            char = self.source[pos];
        }
        while ((char >= '0' and char <= '9')) {
            pos = try self.increment_pos();
            char = self.source[pos];
        }
    }

    self.decrement_pos();
    return is_float;
}

fn eat_till_delimiter(self: *JsonLexer) !usize {
    var pos = try self.increment_pos();
    var char = self.source[pos];
    while (char != ',' and char != ':' and char != '}' and char != ']' and char != ' ') {
        pos = try self.increment_pos();
        char = self.source[pos];
    }
    self.decrement_pos();
    return pos;
}

fn eat_till_scalar(self: *JsonLexer, char: u8) !usize {
    var pos = try self.increment_pos();
    while (self.source[pos] != char) {
        pos = try self.increment_pos();
    }
    return pos;
}

fn increment_pos(self: *JsonLexer) !usize {
    const value = self.current_pos;
    self.current_pos += 1;
    if (self.current_pos > self.source.len) {
        return Error.UNEXPECTED_EOF;
    }
    return value;
}

fn decrement_pos(self: *JsonLexer) void {
    self.current_pos -= 1;
}

fn eat_till_valid(self: *JsonLexer) !usize {
    var pos = try self.increment_pos();
    if (pos >= self.source.len) {
        return pos;
    }
    var char = self.source[pos];
    while (char == ' ' or char == '\n' or char == '\t' or char == '\r') {
        pos = try self.increment_pos();
        char = self.source[pos];
    }
    return pos;
}

const std = @import("std");
