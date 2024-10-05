# Using zf as a library

zf is offered as both a Zig module and a C library. zf is allocation free and expects the caller to handle any required allocations.

To add to your project run

```
zig fetch --save git+https://github.com/natecraddock/zf
```

Then in your build.zig file you can use the dependency.

```zig
pub fn build(b: *std.Build) void {
    // ... snip ...

    const ziglua = b.dependency("zf", .{
        .target = target,
        .optimize = optimize,
        .with_tui = false,
    });

    // ... snip ...

    // add the zf module
    exe.root_module.addImport("zf", ziglua.module("zf"));

}
```

In your code zf will be available with `@import("zf")`

See [the source](https://github.com/natecraddock/zf/blob/master/src/zf/zf.zig) for documentation on each function.

## Usage details
**There are a few things that zf expects you to follow when using it as a library. Pay special attention to the `to_lower` parameter.**

The zf API is designed to offer maximum performance. This means the API leaves some decisions to the caller like allocation and tokenizing the input query.

### Function types

The library offers functions two types of functions. One that ranks a slice of tokens, and one that ranks a single token:
* `rank()` and `highlight()` rank and highlight a string against a slice of query tokens.
* `rankToken()` and `highlightToken()` operate on a single token

### Case sensitivity
`to_lower` is an argument in all library ranking functions. When `to_lower` is true, the string is converted to lowercase, but **the tokens are not converted to lowercase**. This is for efficiency reasons. The tokens are known before ranking a list of strings and should be converted to lowercase ahead of time if case insensitive matching is desired.

zf assumes the caller knows when case sensitivity will be enabled, and expects the caller to ensure any tokens are fully lowercase when `to_lower` is true. When `to_lower` is true, nothing needs to be done.

More concretely, calling `rankToken("my/Path/here", "Path", .{})` (case sensitive is false by default) will NOT match. The string `"my/Path/here"` will be converted to lowercase, but the token will remain as `"Path"`.

### Plaintext matching
The high-level `rank()` and `highlight()` functions accept a boolean `plain` parameter. When true filename computations are bypassed.

### The `filename` parameter
The `rankToken()` and `highlightToken` functions accept a filename as a parameter. The filename should be set to null when there is no filename. The reason the library functions do not do this for you is again for efficiency reasons. This would be expensive to compute for each given token. It is expected that the caller will provide the filename when doing the ranking one token at a time.

To disable filename matching (for plaintext strings or for more efficiency) `null` can be passed as the filename.

### Range highlighting

Range highlighting is provided as a separate function and not done in the ranking. The reason it is a separate function is that range calculations are more expensive to compute. Because the normal case is that only a small portion of all candidate lines are shown in a UI, ranking is done separately to keep things performant.

This also makes ranking more performant for callers who do not need range highlight information.

## Example

```zig
const std = @import("std");

const zf = @import("zf");

pub fn main() void {
    // Strings we want to rank
    const strings = [_][]const u8{
        "src/tui/EditBuffer.zig",
        "src/tui/Previewer.zig",
        "src/tui/array_toggle_set.zig",
        "src/tui/candidate.zig",
        "src/tui/main.zig",
        "src/tui/opts.zig",
        "src/tui/ui.zig",
        "src/zf/clib.zig",
        "src/zf/filter.zig",
        "src/zf/zf.zig",
    };

    // Ranking based on a single token
    const query = "tui";
    for (strings) |str| {
        const rank = zf.rankToken(str, query, .{});
        std.debug.print("str: {s} rank: {?}\n", .{ str, rank });
    }

    std.debug.print("\n", .{});

    // Ranking based on multiple tokens
    const query_tokens = [_][]const u8{ "tui", "Pr" };
    for (strings) |str| {
        // Setting to_lower to false because the query tokens are attempting
        // to match with case sensitivity ("Pr")
        const rank = zf.rank(str, &query_tokens, .{ .to_lower = false });
        std.debug.print("str: {s} rank: {?}\n", .{ str, rank });
    }
}
```

Look at the zf TUI source code for more examples on how to use the module.

## C

See the source code of [telescipe-zf-native.nvim](https://github.com/natecraddock/telescope-zf-native.nvim) for a good example of
using zf ranking from C.
