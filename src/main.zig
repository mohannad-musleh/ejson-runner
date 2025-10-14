const std = @import("std");
const builtin = @import("builtin");
const build_zig_zon = @import("build.zig.zon");
const yazap = @import("yazap");

const App = yazap.App;
const Arg = yazap.Arg;

const project_name = @tagName(build_zig_zon.name);
const version = build_zig_zon.version;
const description = build_zig_zon.description;

pub fn main() !u8 {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var app = App.init(gpa, project_name, description);
    defer app.deinit();

    var ejson_runner = app.rootCommand();
    try ejson_runner.addArgs(&[_]Arg{
        Arg.multiValuesPositional("COMMAND", "The command to be executed.", null),
        Arg.singleValueOption("ejson-file", 'f', "Ejson secrets file [REQUIRED]"),
        Arg.singleValueOption("ejson-keys-dir", 'k', "The path to the directory that contains the ejson's private keys."),
        Arg.singleValueOption("ejson-exe", 'e', "Specify the path of \"ejson\" executable (default: \"ejson\", and expected to be available in PATH)"),
        Arg.singleValueOption("include-paths", 'p', "A comma-seperated list of json paths to be included (if not specified, all will be included)."),
        Arg.booleanOption("exclude-shell-vars", 'E', "Exclude all environment variables provided by the current shell"),
        Arg.booleanOption("version", 'v', "Display the version of " ++ project_name),
    });

    const parsed_args = try app.parseProcess();

    if (parsed_args.containsArg("version")) {
        stdout.print("{s}\n", .{version}) catch return 1;
        stdout.flush() catch return 1;

        return 0;
    }

    const cmd = parsed_args.getMultiValues("COMMAND") orelse {
        std.debug.print("Please specify the command to be executed\n", .{});
        return 1;
    };

    const ejson_file = parsed_args.getSingleValue("ejson-file") orelse {
        app.displayHelp() catch {};
        std.debug.print("ERROR: --ejson-file is required\n", .{});
        return 1;
    };

    const ejson_keys_dir = parsed_args.getSingleValue("ejson-keys-dir");
    if (ejson_keys_dir != null and ejson_keys_dir.?.len < 1) {
        std.debug.print("ERROR: --ejson-keys-dir value must not be empty", .{});
        return 1;
    }

    const ejson_exe = parsed_args.getSingleValue("ejson-exe") orelse "ejson";
    if (ejson_exe.len < 1) {
        std.debug.print("ERROR: --ejson-exe value must not be empty", .{});
        return 1;
    }

    const json_paths_str = parsed_args.getSingleValue("include-paths");
    var json_paths_iterator = if (json_paths_str) |jp| std.mem.splitSequence(u8, jp, ",") else null;

    std.debug.print("FILE: {s}\n", .{ejson_file});
    std.debug.print("KEYS_DIR: {s}\n", .{ejson_keys_dir orelse "<nil>"});
    std.debug.print("EXE: {s}\n", .{ejson_exe});
    if (json_paths_iterator) |*it| {
        std.debug.print("Paths:\n", .{});
        while (it.next()) |path| {
            std.debug.print("\t{s}\n", .{path});
        }
    }

    std.debug.print("CMD: ", .{});
    for (cmd) |part| {
        std.debug.print("{s} ", .{part});
    }
    std.debug.print("\n", .{});

    return 0;
}
