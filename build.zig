// Minimal build.zig file for mimalloc.
// Based on CMakeLists.txt but only makes a static build with most options disabled.

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mimalloc-static",
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(b.path("include"));
    lib.addIncludePath(b.path("src"));

    const result = target.result;
    const os = result.os;

    var mi_sources = std.ArrayList([]const u8).init(b.allocator);
    var mi_cflags = std.ArrayList([]const u8).init(b.allocator);
    var mi_libraries = std.ArrayList([]const u8).init(b.allocator);
    defer mi_sources.deinit();
    defer mi_cflags.deinit();
    defer mi_libraries.deinit();

    try mi_sources.appendSlice(&.{
        "src/alloc.c",
        "src/alloc-aligned.c",
        "src/alloc-posix.c",
        "src/arena.c",
        "src/bitmap.c",
        "src/heap.c",
        "src/init.c",
        "src/options.c",
        "src/os.c",
        "src/page.c",
        "src/random.c",
        "src/segment.c",
        "src/segment-map.c",
        "src/stats.c",
        "src/prim/prim.c",
    });

    // Compiler flags
    if (result.isBSD() or os.tag == .linux) {
        try mi_cflags.appendSlice(&.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Wno-unknown-pragmas",
            "-fvisibility=hidden",
            "-Wstrict-prototypes",
        });
    }

    // XXX: Not sure if this is even necessary in zig build. Copied from CMakeLists.txt
    if (os.tag == .windows) {
        try mi_libraries.appendSlice(&.{ "psapi", "shell32", "user32", "advapi32", "bcrypt" });
    } else {
        try mi_libraries.append("pthread");
        if (os.tag == .linux) {
            try mi_libraries.appendSlice(&.{"rt"});
        }
        // XXX: Do atomics need explicit linking?
    }

    lib.addCSourceFiles(.{
        .files = mi_sources.items,
        .flags = mi_cflags.items,
    });
    lib.linkLibC();
    for (mi_libraries.items) |library| {
        lib.linkSystemLibrary(library);
    }
    lib.defineCMacro("MI_STATIC_LIB", "1");

    lib.installHeadersDirectory(b.path("include"), "", .{});

    b.installArtifact(lib);
}
