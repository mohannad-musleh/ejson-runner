const std = @import("std");

pub fn containsScalar(comptime T: type, haystack: []const T, needle: T) bool {
    const info = @typeInfo(T);

    for (haystack) |item| {
        if (info == .pointer and info.pointer.size == .slice) {
            if (std.mem.eql(info.pointer.child, item, needle)) {
                return true;
            }
        } else {
            if (item == needle) {
                return true;
            }
        }
    }

    return false;
}
