const Stack = @import("stack.zig").Stack;
const Lexer = @import("lexer.zig").Lexer;
const Interpriter = @import("interpriter.zig").Interpriter;

const std = @import("std");

pub fn main() !void {
    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();

    var interpriter = Interpriter.init(std.heap.page_allocator);

    while (true) {
        try stdout.writeAll("> ");
        const line = stdin.readUntilDelimiterOrEofAlloc(std.heap.page_allocator, '\n', 1024) catch break;

        var lexer = Lexer.init(line.?);
        try interpriter.interprite(&lexer);
    }
}

test "main" {
    std.testing.refAllDecls(@This());
}
