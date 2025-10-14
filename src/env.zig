const std = @import("std");
const builtin = @import("builtin");
const json = @import("./json.zig");
const slices = @import("./slices.zig");
const strings = @import("./strings.zig");
const SliceOfStringsIterator = slices.SliceOfStringsIterator;

const UnknownTypeBehavior = enum {
    ignore,
    @"error",
};

pub const SetSecretsEnvsOptions = struct {
    pub const default: @This() = .{};

    captialize_keys: bool = true,
    skip_prefixed_with_underscore: bool = true,
    use_nesting_keys_as_prefix: bool = false,
};

pub const SetSecretsEnvsConfig = struct {
    pub const default: @This() = .{};
    options_key: []const u8 = "__options__",
    unknown_field_behavior: UnknownTypeBehavior = .ignore,
    include_paths: ?[]const []const u8 = null,
};

pub fn setSecretsEnvs(
    allocator: std.mem.Allocator,
    env: *std.process.EnvMap,
    key: ?[]const u8,
    value: std.json.Value,
    path: []const []const u8,
    config: SetSecretsEnvsConfig,
    options: SetSecretsEnvsOptions,
) !void {
    const path_type = @TypeOf(path);
    var name: []const u8 = if (key) |k| k else "_";
    var new_path: path_type = path;

    if (key) |k| {
        new_path = try std.mem.concat(allocator, []const u8, &.{ path, &.{name} });

        if (std.mem.eql(u8, k, config.options_key)) {
            return;
        }

        if (options.skip_prefixed_with_underscore and k.len > 0 and k[0] == '_') {
            return;
        }

        if (std.mem.eql(u8, k, "_public_key") and path.len == 0) {
            return;
        }

        if (config.include_paths) |include_paths| {
            var exclude = true;
            var new_path_iter = SliceOfStringsIterator.init(new_path);

            for (include_paths) |include_path| {
                var include_path_iter = std.mem.splitScalar(u8, include_path, '.');
                new_path_iter.reset();

                var matched = true;
                var partial_match = false;
                while (include_path_iter.next()) |path_part| {
                    if (new_path_iter.next()) |new_path_part| {
                        if (std.mem.eql(u8, path_part, new_path_part)) {
                            partial_match = true;
                        } else {
                            matched = false;
                            break;
                        }
                    } else if (partial_match and value == .object) {
                        break;
                    } else {
                        matched = false;
                        break;
                    }
                }

                if (matched) {
                    exclude = false;
                    break;
                }
            }

            if (exclude) {
                return;
            }
        }

        if (options.use_nesting_keys_as_prefix and path.len > 0) {
            name = try std.mem.join(allocator, "_", new_path);
        }

        if (options.captialize_keys) {
            name = try std.ascii.allocUpperString(allocator, name);
        }
        // std.debug.print("NAME: {s}\n", .{name});
    } else if (value != .object) {
        std.debug.print("Key can only be omitted for the root object.\n", .{});
        return error.MissingKey;
    }

    switch (value) {
        .null => {},
        .bool => |inner| try env.put(name, try strings.toString(allocator, inner)),
        .integer => |inner| try env.put(name, try strings.toString(allocator, inner)),
        .float => |inner| try env.put(name, try strings.toString(allocator, inner)),
        .number_string, .string => |inner| try env.put(name, inner),
        // .array => |inner| ...,
        .object => |o| {
            var parsed_user_options: ?*SetSecretsEnvsOptions = null;
            const user_options = o.get(config.options_key);
            if (user_options) |opt| {
                if (opt == .object) {
                    const parsed = try json.jsonValueToStructLeaky(
                        SetSecretsEnvsOptions,
                        allocator,
                        opt,
                        .{ .value_handling = .reference },
                    );
                    parsed_user_options = parsed;
                }
            }

            var it = o.iterator();
            while (it.next()) |v| {
                try setSecretsEnvs(
                    allocator,
                    env,
                    v.key_ptr.*,
                    v.value_ptr.*,
                    new_path,
                    config,
                    if (parsed_user_options) |uo| uo.* else options,
                );
            }
        },
        else => {
            if (builtin.mode == .Debug) {
                std.debug.print("Unsupported type: {s}\n", .{@tagName(value)});
            }
            if (config.unknown_field_behavior == .@"error") {
                return error.UnknownType;
            }
        },
    }
}
