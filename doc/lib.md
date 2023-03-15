# Using zf as a library

zf is offered as both a Zig package and a C library. The library is allocation free and expects the caller to handle any required allocations.

## Usage details
There are a few things that zf expects you to follow when using it as a library. Pay special attention to the `case_sensitive` parameter.

### Function types
The Zig and C APIs are nearly identical. The Zig API takes advantage of Zig's ability to return nullable values and accept slices but otherwise they are the same.

The library offers both high and low level interfaces to zf's ranking algorithm. The high level interfaces (`rank()` and `highlight()`) rank a string against a list of query tokens. The low level functions (`rankToken()` and `highlightToken()`) require more work on the caller's part, but are more flexible.

### Case sensitivity
`case_sensitive` is an argument in all library ranking functions. When `case_sensitive` is false, the tokens **will not be converted to lowercase**. This is for efficiency reasons. zf assumes the caller knows when case sensitivity will be enabled, and expects the caller to ensure any tokens are fully lowercase when `case_sensitive` is false. When `case_sensitive` is true, nothing needs to be done.

More concretely, calling `rankToken("my/Path/here", "Path", false, false)` (case sensitive is false) will NOT match. The string `"my/Path/here"` will be converted to lowercase, but the token will remain as `"Path"`.

### Plaintext matching
The high-level `rank()` and `highlight()` functions accept a boolean `plain` parameter. When true filename computations are bypassed.

### The `filename` parameter
The `rankToken()` and `highlightToken` functions accept a filename as a parameter. The filename should be set to null when there is no filename. The reason the library functions do not do this for you is again for efficiency reasons. This would be expensive to compute for each given token. It is expected that the caller will provide the filename when doing the ranking one token at a time.

To disable filename matching (for plaintext strings or for more efficiency) `null` can be passed as the filename.

### Range highlighting

Range highlighting is provided as a separate function and not done in the ranking. The reason it is a separate function is that range calculations are more expensive to compute. Because the normal case is that only a small portion of all candidate lines are shown in a UI, ranking is done separately to keep things performant.

This also makes ranking more performant for callers who do not need range highlight information.

## Zig

Using zf as a Zig package is straightforward. Download or clone this repo and place in a subdirectory of your project. Assuming zf is placed in a `./lib/zf` directory, use the following to import and compile zf with your Zig project.

```zig
const zf = @import("lib/zf/build.zig");

pub fn build(b: *std.build.Builder) void {
    ...
    exe.addPackage(zf.package);
}
```

See [the library file](https://github.com/natecraddock/zf/blob/master/src/lib.zig) for documentation on each function.

## C

Todo
