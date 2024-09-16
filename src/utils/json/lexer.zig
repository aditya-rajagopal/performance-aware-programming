pub const JsonLexer = @This();

source: []const u8,
pos: usize = 0,
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
    // const p = tracer.trace(.json_lexer, 1).start();
    // defer p.end();
    const pos = self.eat_till_valid() orelse {
        return .{ .tag = .EOF, .start_pos = 0, .end_pos = self.source.len };
    };

    switch (self.source[pos]) {
        '{' => return .{ .tag = .LEFT_BRACKET, .start_pos = pos, .end_pos = pos + 1 },
        '}' => return .{ .tag = .RIGHT_BRACKET, .start_pos = pos, .end_pos = pos + 1 },
        '[' => return .{ .tag = .LEFT_BRACE, .start_pos = pos, .end_pos = pos + 1 },
        ']' => return .{ .tag = .RIGHT_BRACE, .start_pos = pos, .end_pos = pos + 1 },
        ',' => return .{ .tag = .COMMA, .start_pos = pos, .end_pos = pos + 1 },
        ':' => return .{ .tag = .COLON, .start_pos = pos, .end_pos = pos + 1 },
        '"' => {
            const end = self.eat_till_scalar('"') orelse {
                return .{ .tag = .EOF, .start_pos = 0, .end_pos = pos };
            };
            return .{ .tag = .STRING, .start_pos = pos + 1, .end_pos = end };
        },
        '-', '0'...'9' => {
            const is_float = self.eat_number() orelse {
                return .{ .tag = .EOF, .start_pos = 0, .end_pos = pos };
            };

            if (is_float) {
                return .{ .tag = .NUMBER, .start_pos = pos, .end_pos = self.current_pos };
            } else {
                return .{ .tag = .INTEGER, .start_pos = pos, .end_pos = self.current_pos };
            }
        },
        else => {
            const end = self.eat_till_delimiter() orelse {
                return .{ .tag = .EOF, .start_pos = 0, .end_pos = pos };
            };

            const keyword = self.source[pos..end];
            const TokenTag = Keywords.get(keyword);
            if (TokenTag) |tag| {
                return .{ .tag = tag, .start_pos = pos, .end_pos = end };
            } else {
                return .{ .tag = .ILLEGAL, .start_pos = pos, .end_pos = end };
            }
        },
    }
}

// TODO(aditya): Possible performance bottleneck
fn eat_number(self: *JsonLexer) ?bool {
    @setCold(false);

    var pos = self.increment_pos() orelse return null;
    var is_float = false;
    while (((self.source[pos] >= '0' and self.source[pos] <= '9') or self.source[pos] == '.')) {
        if (self.source[pos] == '.') {
            is_float = true;
        }
        pos = self.increment_pos() orelse return null;
    }
    if ((self.source[pos] == 'e' or self.source[pos] == 'E')) {
        pos = self.increment_pos() orelse return null;
        if ((self.source[pos] == '+' or self.source[pos] == '-')) {
            pos = self.increment_pos() orelse return null;
        }
        while ((self.source[pos] >= '0' and self.source[pos] <= '9')) {
            pos = self.increment_pos() orelse return null;
        }
    }

    self.decrement_pos();
    return is_float;
}

fn eat_till_delimiter(self: *JsonLexer) ?usize {
    @setCold(false);
    var pos = self.increment_pos() orelse return null;
    while ((self.source[pos] != ',' and self.source[pos] != ':' and self.source[pos] != '}' and self.source[pos] != ']' and self.source[pos] != ' ')) {
        pos = self.increment_pos() orelse return null;
    }
    self.decrement_pos();
    return pos;
}

fn eat_till_scalar(self: *JsonLexer, char: u8) ?usize {
    var pos = self.increment_pos() orelse return null;
    while (self.source[pos] != char) {
        pos = self.increment_pos() orelse return null;
    }
    return pos;
}

fn increment_pos(self: *JsonLexer) ?usize {
    @setCold(false);
    const value = self.current_pos;
    self.current_pos += 1;
    if (self.current_pos > self.source.len) {
        return null;
    }
    return value;
}

fn decrement_pos(self: *JsonLexer) void {
    self.current_pos -= 1;
}

fn eat_till_valid(self: *JsonLexer) ?usize {
    @setCold(false);
    // const p = tracer.trace(.json_lexer, 1).start();
    // defer p.end();
    var pos = self.increment_pos() orelse return null;
    while (self.source[pos] == ' ' or self.source[pos] == '\n' or self.source[pos] == '\t' or self.source[pos] == '\r') {
        pos = self.increment_pos() orelse return null;
    }
    return pos;
}

const std = @import("std");
const tracer = @import("perf").tracer;
