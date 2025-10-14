const std = @import("std");

pub fn toString(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .int, .float => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .bool => if (value) "true" else "false",
        else => std.fmt.allocPrint(allocator, "{any}", .{value}),
    };
}
