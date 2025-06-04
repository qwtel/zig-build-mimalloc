// Minimal build.zig file for mimalloc.
// Based on CMakeLists.txt but only makes a static build with most options disabled.

const std = @import("std");
const builtin = @import("builtin");

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
        "src/libc.c",
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
    if (result.os.tag.isBSD() or os.tag == .linux) {
        try mi_cflags.appendSlice(&.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Wno-unknown-pragmas",
            "-fvisibility=hidden",
            "-Wstrict-prototypes",
            "-Wno-static-in-inline",
        });
        if (result.abi.isMusl()) {
            try mi_cflags.append("-ftls-model=local-dynamic");
            lib.root_module.addCMacro("MI_LIBC_MUSL", "1");
        } else {
            try mi_cflags.append("-ftls-model=initial-exec");
        }
    }

    // Architecture-specific optimization flags (like MI_OPT_ARCH_FLAGS)
    if (optimize != .Debug) {
        if (result.cpu.arch.isAARCH64()) {
            try mi_cflags.append("-march=armv8.1-a");
        }
    }

    // Add MI_BUILD_RELEASE define for non-debug builds (to match CMake)
    if (optimize != .Debug) {
        lib.root_module.addCMacro("MI_BUILD_RELEASE", "1");
    }

    // XXX: Not sure if this is even necessary in zig build. Copied from CMakeLists.txt
    if (os.tag == .windows) {
        try mi_libraries.appendSlice(&.{ "psapi", "shell32", "user32", "advapi32", "bcrypt" });
    } else {
        try mi_libraries.append("pthread");
        if (os.tag == .linux) {
            try mi_libraries.appendSlice(&.{"rt"});
        }
        if (shouldLinkLibAtomic(result)) {
            try mi_libraries.appendSlice(&.{"atomic"});
        }
    }

    lib.addCSourceFiles(.{
        .files = mi_sources.items,
        .flags = mi_cflags.items,
    });

    lib.linkLibC();

    for (mi_libraries.items) |library| {
        lib.linkSystemLibrary(library);
    }
    lib.root_module.addCMacro("MI_STATIC_LIB", "1");
    lib.root_module.addCMacro("__DATE__", "\"2025-06-03\"");
    lib.root_module.addCMacro("__TIME__", "\"11:14:00\"");

    lib.installHeadersDirectory(b.path("include"), "", .{});

    b.installArtifact(lib);
}

// Helper function to determine if libatomic should be linked
fn shouldLinkLibAtomic(target: std.Target) bool {
    return switch (target.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => true, // ARM 32-bit
        .aarch64, .aarch64_be => false, // ARM 64-bit typically has native atomics
        .riscv32, .riscv64 => true, // RISC-V might need libatomic on some systems
        else => false, // Assume x86, x86_64, and others have native atomics
    };
}
