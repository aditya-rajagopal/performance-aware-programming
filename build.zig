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
    const sim = b.addExecutable(.{
        .name = "sim8086",
        .root_source_file = b.path("src/sim8086/sim.zig"),
        .target = target,
        .optimize = optimize,
    });

    sim.root_module.addImport("sim8086", sim8086);
    sim.root_module.addImport("utils", utils);
    b.installArtifact(sim);

    const sim_cmd = b.addRunArtifact(sim);
    sim_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        sim_cmd.addArgs(args);
    }

    const data_gen = b.addExecutable(.{
        .name = "haversine_data_gen",
        .root_source_file = b.path("src/haversine/haversine_gen.zig"),
        .target = target,
        .optimize = optimize,
    });

    data_gen.root_module.addImport("utils", utils);
    b.installArtifact(data_gen);

    const data_gen_cmd = b.addRunArtifact(data_gen);
    data_gen_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        data_gen_cmd.addArgs(args);
    }

    const parse = b.addExecutable(.{
        .name = "haversine_parse",
        .root_source_file = b.path("src/haversine/haversine_parse.zig"),
        .target = target,
        .optimize = optimize,
    });

    parse.root_module.addImport("utils", utils);
    parse.root_module.addImport("perf", perf);
    b.installArtifact(parse);

    const parse_cmd = b.addRunArtifact(parse);
    parse_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        parse_cmd.addArgs(args);
    }

    const f_read = b.addExecutable(.{
        .name = "file_read_test",
        .root_source_file = b.path("src/moving_data/file_read_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    f_read.root_module.addImport("utils", utils);
    f_read.root_module.addImport("perf", perf);
    b.installArtifact(f_read);

    const f_read_cmd = b.addRunArtifact(f_read);
    f_read_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        f_read_cmd.addArgs(args);
    }

    const page_file = b.addExecutable(.{
        .name = "page_file_test",
        .root_source_file = b.path("src/moving_data/page_file_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    page_file.root_module.addImport("utils", utils);
    page_file.root_module.addImport("perf", perf);
    b.installArtifact(page_file);

    const page_file_cmd = b.addRunArtifact(page_file);
    page_file_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        page_file_cmd.addArgs(args);
    }

    const write_bytes = b.addExecutable(.{
        .name = "write_bytes_test",
        .root_source_file = b.path("src/moving_data/write_buffer_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    write_bytes.root_module.addImport("utils", utils);
    write_bytes.root_module.addImport("perf", perf);
    b.installArtifact(write_bytes);

    const write_bytes_cmd = b.addRunArtifact(write_bytes);
    write_bytes_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        write_bytes_cmd.addArgs(args);
    }
    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Steps -----------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const sim_step = b.step("sim", "Run the simulation application");
    sim_step.dependOn(&sim_cmd.step);

    const data_gen_step = b.step("data-gen", "Generate haversine data");
    data_gen_step.dependOn(&data_gen_cmd.step);

    const parse_step = b.step("parser", "Parse haversine data");
    parse_step.dependOn(&parse_cmd.step);

    const f_read_step = b.step("f_test", "Repetition testing of file read");
    f_read_step.dependOn(&f_read_cmd.step);

    const page_file_step = b.step("page_file", "Repetition testing of file read");
    page_file_step.dependOn(&page_file_cmd.step);

    const write_bytes_step = b.step("write_bytes", "Repetition testing of file read");
    write_bytes_step.dependOn(&write_bytes_cmd.step);
    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Tests -----------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const utils_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/utils/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    utils_unit_tests.root_module.addImport("perf", perf);

    const run_utils_unit_tests = b.addRunArtifact(utils_unit_tests);
    run_utils_unit_tests.has_side_effects = true;

    const sim8086_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/sim8086/sim8086.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim8086_unit_tests.root_module.addImport("utils", utils);

    const run_sim8086_unit_tests = b.addRunArtifact(sim8086_unit_tests);
    run_sim8086_unit_tests.has_side_effects = true;

    const haversine_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/haversine/haversine_parse.zig"),
        .target = target,
        .optimize = optimize,
    });
    haversine_unit_tests.root_module.addImport("utils", utils);
    haversine_unit_tests.root_module.addImport("perf", perf);

    const run_haversine_unit_tests = b.addRunArtifact(haversine_unit_tests);
    run_haversine_unit_tests.has_side_effects = true;

    const sim_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/sim8086/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_unit_tests.root_module.addImport("sim8086", sim8086);

    const run_sim_unit_tests = b.addRunArtifact(sim_unit_tests);
    run_sim_unit_tests.has_side_effects = true;

    const perf_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/perf/perf.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_perf_unit_tests = b.addRunArtifact(perf_unit_tests);
    run_perf_unit_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_utils_unit_tests.step);
    test_step.dependOn(&run_sim8086_unit_tests.step);
    test_step.dependOn(&run_sim_unit_tests.step);
    test_step.dependOn(&run_haversine_unit_tests.step);
    test_step.dependOn(&run_perf_unit_tests.step);
}
