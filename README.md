# json-runner

Run any command with [`ejson`](https://github.com/Shopify/ejson) secrets
available as environment variables for that command (scoped to the command
only, no other commands can access them. using `execve`).

# Build project

```shell
zig build
```

The output executable will be stored in `./zig-out/bin/ejson_runner`.


## run the project
If you want to build and run the project immediately, use `run` build subcommand.

```shell
zig build run
```
> [!NOTE]
> to pass any command arguments/flags, add `--` to the end of the command
> followed by the arguments/flags you want.
