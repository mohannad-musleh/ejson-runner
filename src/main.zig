const std = @import("std");
const builtin = @import("builtin");
const build_zig_zon = @import("build.zig.zon");
const argsParser = @import("args");
const env = @import("./env.zig");

const project_name = @tagName(build_zig_zon.name);
const version = build_zig_zon.version;
const description = build_zig_zon.description;

const Options = struct {
    @"ejson-file": ?[]const u8 = null,
    @"ejson-keys-dir": ?[]const u8 = null,
    @"ejson-exe": []const u8 = "ejson",
    @"include-paths": ?[]const u8 = null,
    @"exclude-shell-vars": bool = false,
    help: bool = false,
    version: bool = false,

    pub const shorthands = .{
        .h = "help",
        .v = "version",
        .f = "ejson-file",
        .k = "ejson-keys-dir",
        .e = "ejson-exe",
        .p = "include-paths",
        .E = "exclude-shell-vars",
    };

    pub const meta = .{
        .usage_summary = "[OPTIONS] <command>",
        .full_text = description ++ "\n\nNOTE: If you want to run a command that has a similar options/flags as the " ++ project_name ++ ", add \"--\" before the command.",
        .option_docs = .{
            .@"ejson-file" = "Ejson secrets file [REQUIRED]",
            .@"ejson-keys-dir" = "The path to the directory that contains the ejson's private keys.",
            .@"ejson-exe" = "Specify the path of \"ejson\" executable (default: \"ejson\", and expected to be available in PATH).",
            .@"include-paths" = "A comma-seperated list of json paths to be included (if not specified, all will be included).",
            .@"exclude-shell-vars" = "Exclude all environment variables provided by the current shell",
            .help = "Print this help and exit",
            .version = "Display the version of " ++ project_name,
        },
    };
};

pub fn main() u8 {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const parsed_args = argsParser.parseForCurrentProcess(Options, arena, .print) catch return 1;
    const options = parsed_args.options;
    const positionals = parsed_args.positionals;
    defer parsed_args.deinit();

    if (options.help) {
        argsParser.printHelp(
            Options,
            parsed_args.executable_name orelse project_name,
            stdout,
        ) catch return 1;
        stdout.flush() catch return 1;
        return 0;
    }

    if (options.version) {
        stdout.print("{s}\n", .{version}) catch return 1;
        stdout.flush() catch return 1;

        return 0;
    }

    const ejson_file = options.@"ejson-file" orelse {
        std.debug.print("ERROR: --ejson-file is required\n", .{});
        return 1;
    };

    const ejson_keys_dir = options.@"ejson-keys-dir";
    if (ejson_keys_dir != null and ejson_keys_dir.?.len < 1) {
        std.debug.print("ERROR: --ejson-keys-dir value must not be empty", .{});
        return 1;
    }

    const ejson_exe = options.@"ejson-exe";
    if (ejson_exe.len < 1) {
        std.debug.print("ERROR: --ejson-exe value must not be empty", .{});
        return 1;
    }

    const ejson_secrets = readEjsonFile(arena, ejson_file, ejson_exe, ejson_keys_dir) catch |err| {
        std.debug.print("ERROR: Something went wrong while reading the secrets from ejson file: {s}\n", .{@errorName(err)});
        return 1;
    };

    if (positionals.len < 1) {
        std.debug.print("Please specify the command to be executed\n", .{});
        return 1;
    }

    var cmd_args = std.ArrayList([:0]const u8).initCapacity(arena, positionals.len) catch {
        std.debug.print("OOM\n", .{});
        return 1;
    };

    for (positionals) |cmd_part| cmd_args.append(arena, cmd_part) catch {
        std.debug.print("OOM\n", .{});
        return 1;
    };

    var config = env.SetSecretsEnvsConfig{};
    var paths_list: ?std.ArrayList([]const u8) = null;
    if (options.@"include-paths") |paths_str| {
        var it = std.mem.splitSequence(u8, paths_str, ",");
        paths_list = std.ArrayList([]const u8).initCapacity(arena, 5) catch {
            std.debug.print("OOM\n", .{});
            return 1;
        };

        while (it.next()) |json_path| {
            const trimmed_path = std.mem.trim(u8, json_path, " ");
            if (trimmed_path.len < 1) continue;

            paths_list.?.append(arena, trimmed_path) catch {
                std.debug.print("OOM\n", .{});
                return 1;
            };
        }

        config.include_paths = paths_list.?.items;
    }

    var cmd_env = blk: {
        var cmd_env_temp = if (options.@"exclude-shell-vars")
            std.process.EnvMap.init(arena)
        else
            std.process.getEnvMap(arena) catch |err| {
                std.debug.print("Failed to get env map: {s}\n", .{@errorName(err)});
                return 1;
            };

        env.setSecretsEnvs(arena, &cmd_env_temp, null, ejson_secrets.value, &[_][]const u8{}, config, .default) catch |err| {
            std.debug.print("Failed to fill the secrets in the env map object: {s}\n", .{@errorName(err)});
            return 1;
        };

        if (paths_list) |*l| {
            config.include_paths = null;
            l.deinit(arena);
            paths_list = null;
        }

        break :blk &cmd_env_temp;
    };

    defer cmd_env.deinit();

    const e = std.process.execve(arena, cmd_args.items, cmd_env);
    switch (e) {
        error.FileNotFound => {
            std.debug.print("\"{s}\" not found.\n", .{cmd_args.items[0]});
            return 1;
        },
        else => {
            std.debug.print("ERROR: {any}\n", .{e});
            return 1;
        },
    }

    return 0;
}

fn readEjsonFile(
    gpa: std.mem.Allocator,
    ejson_file: []const u8,
    ejson_cmd: []const u8,
    ejson_keys_dir: ?[]const u8,
) !std.json.Parsed(std.json.Value) {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var ejson_cmd_args = try std.ArrayList([]const u8).initCapacity(arena, 5);
    try ejson_cmd_args.append(arena, ejson_cmd);
    if (ejson_keys_dir) |kdir| {
        try ejson_cmd_args.append(arena, "-keydir");
        try ejson_cmd_args.append(arena, kdir);
    }
    try ejson_cmd_args.append(arena, "decrypt");
    try ejson_cmd_args.append(arena, ejson_file);
    const result = try std.process.Child.run(.{
        .allocator = arena,
        .argv = try ejson_cmd_args.toOwnedSlice(arena),
    });

    const command_failed = switch (result.term) {
        .Exited => |exit_code| exit_code != 0,
        else => true,
    };

    if (command_failed or result.stderr.len > 0) {
        const error_message = if (result.stderr.len > 0)
            result.stderr
        else if (result.stdout.len > 0)
            result.stdout
        else
            "Failed to run command";
        std.debug.print("ERROR: {s}\n", .{error_message});
        return error.EjsonCommandError;
    } else if (result.stdout.len < 1) {
        std.debug.print("ERROR: {s}\n", .{"Empty output from ejson command"});
        return error.EjsonCommandError;
    }

    var secrets = try std.json.parseFromSlice(
        std.json.Value,
        gpa,
        result.stdout,
        .{ .parse_numbers = false },
    );
    errdefer secrets.deinit();

    return secrets;
}
