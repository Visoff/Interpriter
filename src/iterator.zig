const std = @import("std");

pub fn Iterator(comptime T: type) type {
    return struct {
        const Self = @This();
        head: ?*Node,
        end: ?*Node,
        allocator: std.mem.Allocator,

        const Node = struct {
            value: T,
            next: ?*Node,
            prev: ?*Node,
        };

        pub fn next(self: *Self) ?T {
            if (self.head) |head| {
                self.head = head.next;
                return head.value;
            }
            return null;
        }

        pub fn peek(self: *Self) ?T {
            if (self.head) |head| {
                return head.value;
            }
            return null;
        }

        pub fn push(self: *Self, value: T) !void {
            var node = try self.allocator.create(Node);
            node.value = value;
            node.next = null;
            node.prev = self.end;
            if (self.end) |end| {
                end.next = node;
            }
            self.end = node;
            if (self.head == null) {
                self.head = node;
            }
        }

        pub fn push_left(self: *Self, value: T) !void {
            var node = try self.allocator.create(Node);
            node.value = value;
            node.next = self.head;
            node.prev = null;
            if (self.head) |head| {
                head.prev = node;
            }
            self.head = node;
            if (self.end == null) {
                self.end = node;
            }
        }

        pub fn cut(self: *Self, move: fn (*T) bool) Self {
            var ptr = self.head;
            while (ptr) |node| : (ptr = node.next) {
                if (!move(&node.value)) {
                    if (node.prev) |prev| {
                        defer {
                            self.head = node;
                            node.prev = null;
                            prev.next = null;
                        }
                        return Self{ .head = self.head, .end = prev, .allocator = self.allocator };
                    }
                    return Self{ .head = null, .end = null, .allocator = self.allocator };
                }
            }
            defer {
                self.head = null;
                self.end = null;
            }
            return Self{ .head = self.head, .end = self.end, .allocator = self.allocator };
        }

        pub fn to_slice(self: *const Self) ![]T {
            var ptr = self.head;
            var result = std.ArrayList(T).init(self.allocator);
            while (ptr) |node| : (ptr = node.next) {
                try result.append(node.value);
            }
            return result.toOwnedSlice();
        }

        pub fn from_slice(self: *Self, slice: []T) !void {
            for (slice) |value| {
                try self.push(value);
            }
        }

        pub fn print(self: *const Self) void {
            var ptr = self.head;
            while (ptr) |node| : (ptr = node.next) {
                std.debug.print("{any} -> ", .{node.value});
            }
            std.debug.print("null\n", .{});
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .head = null,
                .end = null,
                .allocator = allocator,
            };
        }
    };
}
