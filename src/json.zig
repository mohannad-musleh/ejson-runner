const std = @import("std");
const mem = @import("./mem.zig");

pub const ValueHandling = enum { copy, reference };

pub const FieldsSet = []const []const u8;

pub const JsonValueToStructOptions = struct {
    value_handling: ValueHandling = .copy,
    exclude_fields: ?FieldsSet = null,
};

/// Convert `std.json.Value` to a struct. Allocations made during this
/// operation are not carefully tracked and may not be possible to individually
/// clean up. It is recommended to use a std.heap.ArenaAllocator or similar.
pub fn jsonValueToStructLeaky(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: std.json.Value,
    options: JsonValueToStructOptions,
) !*T {
    const info = @typeInfo(T);

    if (@typeInfo(T) != .@"struct") {
        @compileError("T should be a struct, got " ++ @typeName(T) ++ " instead.");
    }

    if (value != .object) {
        return error.JsonValueIsNotObject;
    }

    const obj = value.object;

    const result: *T = try allocator.create(T);
    errdefer allocator.destroy(result);

    inline for (info.@"struct".fields) |field| {
        if (options.exclude_fields != null and mem.containsScalar([]const u8, options.exclude_fields.?, field.name)) {
            @field(result, field.name) = field.defaultValue().?;
        } else {
            if (obj.get(field.name)) |field_value| {
                const field_type = field.type;
                const field_type_info = @typeInfo(field_type);
                switch (field_value) {
                    .integer => |inner| {
                        if (field_type_info == .int) {
                            @field(result, field.name) = @intCast(inner);
                        } else {
                            std.debug.print("The field \"{s}\" expectes value of type \"{s}\" but got a {s}:{any} value instead\n", .{ field.name, @typeName(field.type), @typeName(@TypeOf(inner)), inner });
                            return error.IncompatibleFieldValueType;
                        }
                    },
                    .float => |inner| {
                        if (field_type_info == .float) {
                            @field(result, field.name) = @floatCast(inner);
                        } else {
                            std.debug.print("The field \"{s}\" expectes value of type \"{s}\" but got a {s}:{any} value instead\n", .{ field.name, @typeName(field.type), @typeName(@TypeOf(inner)), inner });
                            return error.IncompatibleFieldValueType;
                        }
                    },
                    .number_string => |inner| {
                        if (field_type_info == .int) {
                            const parsed_value = std.fmt.parseInt(field.type, inner, 0);
                            if (parsed_value) |pv| {
                                @field(result, field.name) = pv;
                            } else |err| {
                                std.debug.print("Failed to convert \"{s}\" string to integer: {s}\n", .{ inner, @errorName(err) });
                                return error.IncompatibleFieldValueType;
                            }
                        } else if (field_type_info == .float) {
                            const parsed_value = std.fmt.parseFloat(field.type, inner);
                            if (parsed_value) |pv| {
                                @field(result, field.name) = pv;
                            } else |err| {
                                std.debug.print("Failed to convert \"{s}\" string to float: {s}\n", .{ inner, @errorName(err) });
                                return error.IncompatibleFieldValueType;
                            }
                        } else {
                            std.debug.print("The field \"{s}\" expectes value of type \"{s}\" but got a {s}:{any} value instead\n", .{ field.name, @typeName(field.type), @typeName(@TypeOf(inner)), inner });
                            return error.IncompatibleFieldValueType;
                        }
                    },
                    .bool => |inner| {
                        if (field_type_info == .bool) {
                            @field(result, field.name) = inner;
                        } else {
                            std.debug.print("The field \"{s}\" expectes value of type \"{s}\" but got a {s}:{any} value instead\n", .{ field.name, @typeName(field.type), @typeName(@TypeOf(inner)), inner });
                            return error.IncompatibleFieldValueType;
                        }
                    },
                    .string => |inner| {
                        if (field_type_info == .int) {
                            const parsed_value = std.fmt.parseInt(field.type, inner, 0);
                            if (parsed_value) |pv| {
                                @field(result, field.name) = pv;
                            } else |err| {
                                std.debug.print("Failed to convert \"{s}\" string to integer: {s}\n", .{ inner, @errorName(err) });
                                return error.IncompatibleFieldValueType;
                            }
                        } else if (field_type_info == .float) {
                            const parsed_value = std.fmt.parseFloat(field.type, inner);
                            if (parsed_value) |pv| {
                                @field(result, field.name) = pv;
                            } else |err| {
                                std.debug.print("Failed to convert \"{s}\" string to float: {s}\n", .{ inner, @errorName(err) });
                                return error.IncompatibleFieldValueType;
                            }
                        } else if (field.type == @TypeOf(inner)) {
                            if (options.value_handling == .reference) {
                                @field(result, field.name) = inner;
                            } else {
                                @field(result, field.name) = try allocator.dupe(u8, inner);
                            }
                        } else {
                            std.debug.print("The field \"{s}\" expectes value of type \"{s}\" but got a {s}:{any} value instead\n", .{ field.name, @typeName(field.type), @typeName(@TypeOf(inner)), inner });
                            return error.IncompatibleFieldValueType;
                        }
                    },
                    .array => |inner| {
                        if (field.type == @TypeOf(inner)) {
                            @field(result, field.name) = inner;
                        } else {
                            std.debug.print("The field \"{s}\" expectes value of type \"{s}\" but got a {s}:{any} value instead\n", .{ field.name, @typeName(field.type), @typeName(@TypeOf(inner)), inner });
                            return error.IncompatibleFieldValueType;
                        }
                    },
                    // .object => |inner| {},
                    else => {
                        return error.TypeNotSupported;
                    },
                }
            } else if (field.defaultValue() == null) {
                std.debug.print("Value for field \"{s}\" is missing\n", .{field.name});
                return error.MissingField;
            }
        }
    }

    return result;
}
