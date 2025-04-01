// A script to build and test the chibi using Zig build system.

const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("chibi", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const t = target.result;

    var linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode") orelse .dynamic;
    if(t.os.tag == .windows) {linkage = .static;}
    const ulimit = b.option(bool, "ulimit", "ulimit") orelse false;

    const libchibi = b.addLibrary(.{
        .linkage = linkage,
        .name = "chibi-scheme",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    libchibi.addIncludePath(upstream.path("include"));
    libchibi.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "gc.c",
            "sexp.c",
        },
        .flags = if(ulimit) &.{"-DSEXP_USE_LIMITED_MALLOC", "-DSEXP_USE_NTPGETTIME" ,"-DSEXP_USE_INTTYPES",}
            else &.{"-DSEXP_USE_NTPGETTIME" ,"-DSEXP_USE_INTTYPES",},
    });
    libchibi.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "bignum.c",
            "gc_heap.c",
            "opcodes.c",
            "vm.c",
            "eval.c",
            "simplify.c",
        },
        .flags = &.{
            "-DSEXP_USE_NTPGETTIME" ,"-DSEXP_USE_INTTYPES",
        }
    });

    libchibi.installHeader(upstream.path("include/chibi/sexp.h"), "chibi/sexp.h");
    libchibi.installHeader(upstream.path("include/chibi/features.h"), "chibi/features.h");

    const module_path = blk: {
        const moddir = std.mem.concat(b.allocator, u8, &.{b.install_path, "/share/chibi"}) catch unreachable;
        const binmoddir = std.mem.concat(b.allocator, u8, &.{b.lib_dir, "/chibi"}) catch unreachable;
        const snowmoddir = std.mem.concat(b.allocator, u8, &.{b.install_path, "/share/snow"}) catch unreachable;
        const snowbinmoddir = std.mem.concat(b.allocator, u8, &.{b.lib_dir, "/snow"}) catch unreachable;
        break :blk std.mem.join(b.allocator, ":", &.{
            moddir, binmoddir, snowmoddir, snowbinmoddir
        }) catch unreachable;
    };
    const install_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("include/chibi/install.h.in") },
        .include_path = "chibi/install.h",
    }, .{
        .CMAKE_SHARED_LIBRARY_SUFFIX = libchibi.out_filename[std.mem.indexOfScalar(u8, libchibi.out_filename, '.') orelse 0..],
        .default_module_path = module_path,
        .platform = std.enums.tagName(std.Target.Os.Tag, t.os.tag),
        .CMAKE_SYSTEM_PROCESSOR = std.enums.tagName(std.Target.Cpu.Arch, t.cpu.arch),
        .CMAKE_PROJECT_VERSION = "0.11.0",
        .release = "git",
    });
    libchibi.addConfigHeader(install_h);
    libchibi.installConfigHeader(install_h);
    libchibi.installHeader(upstream.path("include/chibi/bignum.h"), "chibi/bignum.h");
    libchibi.installHeader(upstream.path("include/chibi/eval.h"), "chibi/eval.h");
    libchibi.installHeader(upstream.path("include/chibi/gc_heap.h"), "chibi/gc_heap.h");

    b.installArtifact(libchibi);

    const chibi = b.addExecutable(.{
        .linkage = linkage,
        .name = if(linkage == .static) "chibi-scheme-static"
            else if (ulimit) "chibi-scheme-ulimit"
            else "chibi-scheme",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    chibi.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "main.c"
        },
    });
    chibi.linkLibrary(libchibi);

    b.installArtifact(chibi);

    const weak = b.addLibrary(.{.linkage = linkage, .name = "weak",
        .root_module = b.createModule(.{.target = target, .optimize = optimize,}),
    });
    installLibrary(b, weak, upstream, "lib/chibi/weak.c", "lib/chibi/chibi", libchibi);

    const heap_stats = b.addLibrary(.{.linkage = linkage, .name = "heap-stats",
        .root_module = b.createModule(.{.target = target,.optimize = optimize,}),
    });
    installLibrary(b, heap_stats, upstream, "lib/chibi/heap-stats.c", "lib/chibi/chibi", libchibi);

    const disasm = b.addLibrary(.{.linkage = linkage, .name = "disasm",
        .root_module = b.createModule(.{.target = target,.optimize = optimize,}),
    });
    installLibrary(b, disasm, upstream, "lib/chibi/disasm.c", "lib/chibi/chibi", libchibi);

    const ast = b.addLibrary(.{.linkage = linkage, .name = "ast",
        .root_module = b.createModule(.{.target = target,.optimize = optimize,}),
    });
    installLibrary(b, ast, upstream, "lib/chibi/ast.c", "lib/chibi/chibi", libchibi);

    const json = b.addLibrary(.{.linkage = linkage, .name = "json",
        .root_module = b.createModule(.{.target = target,.optimize = optimize,}),
    });
    installLibrary(b, json, upstream, "lib/chibi/json.c", "lib/chibi/chibi", libchibi);

    const threads = b.addLibrary(.{.linkage = linkage, .name = "threads",
        .root_module = b.createModule(.{.target = target,.optimize = optimize,}),
    });
    installLibrary(b, threads, upstream, "lib/srfi/18/threads.c", "lib/chibi/srfi/18", libchibi);

    const time = b.addLibrary(.{.linkage = linkage, .name = "time",
        .root_module = b.createModule(.{.target = target,.optimize = optimize,}),
    });
    installLibrary(b, time, upstream, "lib/scheme/time.c", "lib/chibi/scheme", libchibi);
}

fn installLibrary(b: *std.Build, lib: *std.Build.Step.Compile, upstream: *std.Build.Dependency, file: []const u8, dest_dir: []const u8, libchibi: *std.Build.Step.Compile) void {
    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{file},
        .flags = &.{"-DSEXP_USE_NTPGETTIME" ,"-DSEXP_USE_INTTYPES",},
    });
    lib.addIncludePath(upstream.path("include"));
    lib.linkLibrary(libchibi);

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{.override = .{.custom = dest_dir}},
    });
    b.getInstallStep().dependOn(&install.step);
}
