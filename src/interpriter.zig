const Token = @import("tokens.zig").Token;
const TokenIterator = @import("iterator.zig").Iterator(Token);
const Value = @import("tokens.zig").Value;
const lexer = @import("lexer.zig");
const std = @import("std");

const Error = error{
    SyntaxError,
    OutOfMemory,
};

pub const Env = struct {
    variables: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Env {
        return .{
            .variables = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Env) void {
        self.variables.deinit();
    }

    pub fn write(self: *Env, name: []const u8, value: Value) !void {
        try self.variables.put(name, value);
    }

    pub fn get(self: *const Env, name: []const u8) ?Value {
        return self.variables.get(name);
    }

    pub fn has(self: *const Env, name: []const u8) bool {
        return self.variables.contains(name);
    }
};

pub const Interpriter = struct {
    env: Env,

    fn run(self: *Interpriter, tokens: *TokenIterator) Error!void {
        while (tokens.next()) |token| {
            //std.debug.print("{}\n", .{token});
            switch (token) {
                .Let => {
                    const name = tokens.next().?;
                    if (name != .Ident) return error.SyntaxError;
                    if (tokens.next().? != .Equal) return error.SyntaxError;
                    var value_tokens = tokens.cut(struct {
                        pub fn takes(t: *Token) bool {
                            return switch (t.*) {
                                .Semicolon, .EOF => false,
                                else => true,
                            };
                        }
                    }.takes);
                    const value = try self.eval(&value_tokens);
                    try self.env.write(name.Ident, value);
                    continue;
                },
                .Ident => |ident| {
                    if (self.env.has(ident)) {
                        //std.debug.print("{any}\n", .{tokens.peek().?});
                        if (tokens.next()) |t| {
                            switch (t) {
                                .Equal => {
                                    const value = try self.eval(tokens);
                                    try self.env.write(ident, value);
                                    continue;
                                },
                                .Operator => |op| {
                                    if (op.len == 2 and op[1] == '=') {
                                        try tokens.push_left(.{ .Operator = op[0..1] });
                                        try tokens.push_left(.{ .Ident = ident });
                                        const value = try self.eval(tokens);
                                        try self.env.write(ident, value);
                                        continue;
                                    }
                                },
                                .Semicolon, .EOF => std.debug.print("{}\n", .{self.env.get(ident).?}),
                                .LParen => {
                                    try tokens.push_left(.LParen);
                                    try tokens.push_left(.{ .Ident = ident });
                                    std.debug.print("{}\n", .{try self.eval(tokens)});
                                },
                                else => return error.SyntaxError,
                            }
                            continue;
                        }
                        continue;
                    }
                    return error.SyntaxError;
                },
                .Fn => {
                    if (tokens.next()) |t| {
                        switch (t) {
                            .Ident => |ident| {
                                try self.env.write(ident, try self.eval_fn(tokens));
                                //std.debug.print("{}\n", .{self.env.get(ident).?});
                                continue;
                            },
                            else => return error.SyntaxError,
                        }
                        continue;
                    }
                    return error.SyntaxError;
                },
                .Return => {
                    const return_value = try self.eval(tokens);
                    try self.env.write("return", return_value);
                    return;
                },
                .Semicolon => continue,
                .EOF => break,
                else => {},
            }
        }
    }

    fn eval_fn(_: *Interpriter, tokens: *TokenIterator) !Value {
        _ = tokens.cut(struct {
            pub fn takes(t: *Token) bool {
                return switch (t.*) {
                    .Semicolon, .EOF, .RParen => false,
                    else => true,
                };
            }
        }.takes);
        var arg_tokens = tokens.cut(struct {
            pub fn takes(t: *Token) bool {
                return switch (t.*) {
                    .Semicolon, .EOF, .RParen => false,
                    else => true,
                };
            }
        }.takes);
        var args = std.ArrayList([]const u8).init(std.heap.page_allocator);
        while (arg_tokens.next()) |arg| {
            switch (arg) {
                .Ident => |ident| try args.append(ident),
                .Comma => continue,
                else => return error.SyntaxError,
            }
        }
        _ = tokens.cut(struct {
            pub fn takes(t: *Token) bool {
                return switch (t.*) {
                    .Semicolon, .EOF, .LBrace => false,
                    else => true,
                };
            }
        }.takes);
        var body = tokens.cut(struct {
            pub fn takes(t: *Token) bool {
                return switch (t.*) {
                    .RBrace => false,
                    else => true,
                };
            }
        }.takes);
        _ = body.next();
        //body.print();
        return .{ .Function = .{ .args = try args.toOwnedSlice(), .body = try body.to_slice() } };
    }

    fn call_fn(_: *Interpriter, func: Value, args: []Value) !Value {
        var tokens = TokenIterator.init(std.heap.page_allocator);
        for (func.Function.args, args) |key, value| {
            try tokens.push(.Let);
            try tokens.push(.{ .Ident = key });
            try tokens.push(.Equal);
            try tokens.push(.{ .Value = value });
            try tokens.push(.Semicolon);
        }
        try tokens.from_slice(func.Function.body);
        try tokens.push(.EOF);
        //tokens.print();
        var interpriter = Interpriter.init(std.heap.page_allocator);
        defer interpriter.deinit();
        try interpriter.run(&tokens);
        if (interpriter.env.get("return")) |value| {
            //std.debug.print("{any}\n", .{value});
            return value;
        }
        return .Undefined;
    }

    fn eval(self: *Interpriter, tokens: *TokenIterator) !Value {
        var result: Value = .Undefined;
        while (tokens.next()) |token| {
            //std.debug.print("{any}\n", .{token});
            switch (token) {
                .Value => |value| {
                    if (result != .Undefined) {
                        return error.SyntaxError;
                    }
                    result = value;
                },
                .Operator => |op| {
                    if (result == .Undefined) {
                        return error.SyntaxError;
                    }
                    const right_side = try self.eval(tokens);
                    switch (result) {
                        .Number => {
                            if (right_side != .Number) {
                                return error.SyntaxError;
                            }
                            if (std.mem.eql(u8, op, "+")) {
                                result.Number += right_side.Number;
                                continue;
                            }
                            if (std.mem.eql(u8, op, "-")) {
                                result.Number -= right_side.Number;
                                continue;
                            }
                            if (std.mem.eql(u8, op, "*")) {
                                result.Number *= right_side.Number;
                                continue;
                            }
                            if (std.mem.eql(u8, op, "/")) {
                                result.Number /= right_side.Number;
                                continue;
                            }
                        },
                        .String => {
                            if (right_side != .String) {
                                return error.SyntaxError;
                            }
                            if (std.mem.eql(u8, op, "+")) {
                                result.String = try std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{ result.String, right_side.String });
                                continue;
                            }
                            return error.SyntaxError;
                        },
                        else => return error.SyntaxError,
                    }
                },
                .Ident => |ident| {
                    if (self.env.has(ident)) {
                        const value = self.env.get(ident).?;
                        if (result == .Undefined) {
                            if (value == .Function) {
                                if (tokens.peek()) |t| {
                                    if (t != .LParen) {
                                        return error.SyntaxError;
                                    }
                                    _ = tokens.next();
                                    var args = std.ArrayList(Value).init(std.heap.page_allocator);
                                    while (tokens.next()) |tkn| {
                                        switch (tkn) {
                                            .RParen => break,
                                            .Comma => continue,
                                            else => try args.append(try self.eval(tokens)),
                                        }
                                    }
                                    _ = tokens.next();
                                    result = try self.call_fn(value, args.items);
                                    continue;
                                }
                            }
                            result = value;
                        }
                    }
                },
                .LParen => {
                    var value_tokens = TokenIterator.init(std.heap.page_allocator);
                    var parens: u32 = 1;
                    while (tokens.next()) |t| {
                        if (parens == 0) break;
                        switch (t) {
                            .EOF, .Semicolon => break,
                            .LParen => parens += 1,
                            .RParen => parens -= 1,
                            else => try value_tokens.push(t),
                        }
                    }
                    result = try self.eval(&value_tokens);
                },
                .Semicolon, .EOF => {
                    try tokens.push_left(.Semicolon);
                    break;
                },
                else => return error.SyntaxError,
            }
        }
        return result;
    }

    pub fn interprite(self: *Interpriter, l: *lexer.Lexer) !void {
        var tokens = TokenIterator.init(std.heap.page_allocator);
        while (try l.next_token()) |token| {
            //std.debug.print("{any}\n", .{token});
            switch (token) {
                .EOF => break,
                else => try tokens.push(token),
            }
        }
        try tokens.push(.EOF);
        try self.run(&tokens);
    }

    pub fn init(allocator: std.mem.Allocator) Interpriter {
        return .{
            .env = Env.init(allocator),
        };
    }

    pub fn deinit(self: *Interpriter) void {
        self.env.deinit();
    }
};

test "assign number" {
    var l = lexer.Lexer.init("let x = (5);");
    var i = Interpriter.init(std.testing.allocator);
    defer i.deinit();
    try i.interprite(&l);
    try std.testing.expect(i.env.has("x"));
    try std.testing.expectEqual(@as(Value, .{ .Number = 5 }), i.env.get("x").?);
}

test "function call" {
    var l = lexer.Lexer.init("fn main() {let a = 5; return a;}; let b = main();");
    var i = Interpriter.init(std.testing.allocator);
    defer i.deinit();
    try i.interprite(&l);
    try std.testing.expect(i.env.has("b"));
    try std.testing.expectEqual(@as(Value, .{ .Number = 5 }), i.env.get("b").?);
}
