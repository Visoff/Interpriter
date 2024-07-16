const tokens = @import("tokens.zig");
const std = @import("std");

fn is_numeric(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn is_alphabetic(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

pub const Lexer = struct {
    input: []const u8,
    ch: u8 = 0,
    pos: usize = 0,

    pub fn init(input: []const u8) Lexer {
        return Lexer{ .input = input, .ch = input[0] };
    }

    fn move(self: *Lexer, n: usize) void {
        self.pos += n;
        self.ch = if (self.pos < self.input.len) self.input[self.pos] else 0;
    }

    pub fn peek(self: *Lexer, n: usize) u8 {
        return if (self.pos + n < self.input.len) self.input[self.pos + n] else 0;
    }

    fn remove_whitespace(self: *Lexer) void {
        while (self.ch == ' ') self.move(1);
    }

    fn read_number(self: *Lexer) f64 {
        var number: f64 = 0;
        var decimals: usize = 0;
        var decimal = false;
        while ((self.ch >= '0' and self.ch <= '9') or self.ch == '.') : (self.move(1)) {
            if (self.ch == '.') {
                if (decimal) break;
                decimal = true;
                continue;
            }
            if (decimal) decimals += 1;
            number = number * 10 + @as(f64, @floatFromInt(self.ch - '0'));
        }
        return number / std.math.pow(f64, 10, @floatFromInt(decimals));
    }

    fn read_string(self: *Lexer) ![]const u8 {
        var result = std.ArrayList(u8).init(std.heap.page_allocator);
        const escape_ch = self.ch;
        self.move(1);
        while (self.ch != escape_ch) : (self.move(1)) {
            if (self.ch == 0) return error.SyntaxError;
            try result.append(self.ch);
        }
        self.move(1);
        return result.toOwnedSlice();
    }

    fn read_ident(self: *Lexer) ![]const u8 {
        var result = std.ArrayList(u8).init(std.heap.page_allocator);
        while (is_alphabetic(self.ch) or is_numeric(self.ch) or self.ch == '_') : (self.move(1)) {
            if (self.ch == 0) break;
            try result.append(self.ch);
        }
        return result.toOwnedSlice();
    }

    pub fn next_token(self: *Lexer) !?tokens.Token {
        self.remove_whitespace();
        const token: tokens.Token = switch (self.ch) {
            0 => .EOF,
            ',' => .Comma,
            '(' => .LParen,
            ')' => .RParen,
            '{' => .LBrace,
            '}' => .RBrace,
            '+', '-', '*', '/' => |op| {
                var operator = std.ArrayList(u8).init(std.heap.page_allocator);
                try operator.append(op);
                if (self.peek(1) == '=') {
                    self.move(2);
                    try operator.append('=');
                }
                return .{ .Operator = try operator.toOwnedSlice() };
            },
            '=' => .Equal,
            ';', '\n' => .Semicolon,
            '\"', '\'' => .{ .Value = .{ .String = try self.read_string() } },
            '0'...'9' => return .{ .Value = .{ .Number = self.read_number() } },
            'a'...'z', 'A'...'Z', '_' => {
                const ident = try self.read_ident();
                if (std.mem.eql(u8, ident, "let")) return .Let;
                if (std.mem.eql(u8, ident, "fn")) return .Fn;
                if (std.mem.eql(u8, ident, "return")) return .Return;
                return .{ .Ident = ident };
            },
            else => .Unsupported,
        };
        self.move(1);
        return token;
    }
};

test "lexer" {
    var lexer = Lexer.init("let x = 5;");
    const expected_tokens = [_]tokens.Token{
        .Let,
        .{ .Ident = "x" },
        .Equal,
        .{ .Value = .{ .Number = 5 } },
        .Semicolon,
        .EOF,
    };
    for (expected_tokens) |expected_token| {
        const token = try lexer.next_token();
        try std.testing.expectEqualDeep(expected_token, token.?);
    }
}
