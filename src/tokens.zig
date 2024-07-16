const std = @import("std");

pub const Value = union(enum) {
    Number: f64,
    String: []const u8,
    Function: struct { args: [][]const u8, body: []Token },
    Undefined: void,
};

pub const Token = union(enum) {
    Value: Value,
    Ident: []const u8,

    Operator: []const u8,
    Comma: void,

    LParen: void,
    RParen: void,
    LBrace: void,
    RBrace: void,
    Semicolon: void,

    Equal: void,
    Let: void,
    Fn: void,
    Return: void,

    EOF: void,

    Unsupported: void,

    pub fn print(self: Token) void {
        std.debug.print("{}", .{self});
    }
};
