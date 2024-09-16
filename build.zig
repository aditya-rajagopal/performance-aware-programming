const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Modules ---------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const perf = b.addModule("perf", .{ .root_source_file = .{ .path = "src/perf/perf.zig" } });

    const utils = b.addModule("utils", .{
        .root_source_file = .{ .path = "src/utils/utils.zig" },
        .imports = &.{.{ .name = "perf", .module = perf }},
    });

    const sim8086 = b.addModule("sim8086", .{
        .root_source_file = .{
            .path = "src/sim8086/sim8086.zig",
        },
        .imports = &.{.{ .name = "utils", .module = utils }},
    });

    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Executables -----------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------

    const Package = struct {
        step: []const u8,
        exe_name: []const u8,
        path: []const u8,
        description: []const u8,
    };
    const packages: []const Package = &[_]Package{
        .{
            .step = "sim",
            .exe_name = "sim8086",
            .path = "src/sim8086/sim.zig",
            .description = "Run the simulation application",
        },
        .{
            .step = "haversine_data_gen",
            .exe_name = "data-gen",
            .path = "src/haversine/haversine_gen.zig",
            .description = "Generate haversine data",
        },
        .{
            .step = "parser",
            .exe_name = "data-parse",
            .path = "src/haversine/haversine_parse.zig",
            .description = "Parse haversine data",
        },
        .{
            .step = "file_read_test",
            .exe_name = "f_test",
            .path = "src/moving_data/file_read_test.zig",
            .description = "Repetition testing of file read",
        },
        .{
            .step = "page_file_test",
            .exe_name = "page_file",
            .path = "src/moving_data/page_file_test.zig",
            .description = "Test page fault rates for touching data",
        },
        .{
            .step = "write_bytes_test",
            .exe_name = "write_bytes",
            .path = "src/moving_data/write_buffer_test.zig",
            .description = "Test writing to a newly allocated buffer forward and backward",
        },
        .{
            .step = "paging",
            .exe_name = "paging",
            .path = "src/moving_data/four_level_paging.zig",
            .description = "Four level paging test",
        },
    };

    inline for (packages) |p| {
        const exe = b.addExecutable(.{
            .name = p.exe_name,
            .root_source_file = b.path(p.path),
            .target = target,
            .optimize = optimize,
        });
        if (std.mem.eql(u8, "sim8086", p.exe_name)) {
            exe.root_module.addImport("sim8086", sim8086);
        }
        exe.root_module.addImport("utils", utils);
        exe.root_module.addImport("perf", perf);

        // Enable asm
        // const waf = b.addWriteFiles();
        // waf.addCopyFileToSource(exe.getEmittedAsm(), p.exe_name ++ ".asm");
        // waf.step.dependOn(&exe.step);
        // b.getInstallStep().dependOn(&waf.step);
        b.installArtifact(exe);
        const exe_cmd = b.addRunArtifact(exe);
        exe_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            exe_cmd.addArgs(args);
        }

        const step = b.step(p.step, p.description);
        step.dependOn(&exe_cmd.step);
    }

    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Tests -----------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    //

    const TestCase = struct {
        name: []const u8,
        root_path: []const u8,
    };

    const tests: []const TestCase = &[_]TestCase{
        .{ .name = "utils", .root_path = "src/utils/utils.zig" },
        .{ .name = "sim8086", .root_path = "src/sim8086/sim8086.zig" },
        .{ .name = "haversine_parse", .root_path = "src/haversine/haversine_parse.zig" },
        .{ .name = "sim", .root_path = "src/sim8086/sim.zig" },
        .{ .name = "perf", .root_path = "src/perf/perf.zig" },
    };
    const test_step = b.step("test", "Run unit tests");

    for (tests) |t| {
        const unit_test = b.addTest(.{
            .root_source_file = b.path(t.root_path),
            .target = target,
            .optimize = optimize,
        });
        if (!std.mem.eql(u8, "utils", t.name)) {
            unit_test.root_module.addImport("utils", utils);
        }
        if (std.mem.eql(u8, "sim", t.name)) {
            unit_test.root_module.addImport("sim8086", sim8086);
        }
        if (!std.mem.eql(u8, "perf", t.name)) {
            unit_test.root_module.addImport("perf", perf);
        }
        const run_test = b.addRunArtifact(unit_test);
        run_test.has_side_effects = true;
        test_step.dependOn(&run_test.step);
    }
}
