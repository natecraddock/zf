# Using zf as a library

Zf is packaged as both a Zig and a C library

## Zig

Using zf as a Zig library is straightforward. Download or clone this repo and place in a subdirectory of your project. Assuming zf is placed in a `./lib/zf` directory, use the following to import and compile zf with your Zig project.

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
