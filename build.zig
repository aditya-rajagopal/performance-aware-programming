const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Modules ---------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const utils = b.addModule("utils", .{ .root_source_file = .{ .path = "src/utils/utils.zig" } });

    const sim8086 = b.addModule("sim8086", .{
        .root_source_file = .{
            .path = "src/sim8086/sim8086.zig",
        },
        .imports = &.{.{ .name = "utils", .module = utils }},
    });

    const haversine = b.addModule("utils", .{ .root_source_file = .{ .path = "src/haversine/haversine.zig" } });

    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Executables -----------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const sim = b.addExecutable(.{
        .name = "sim8086",
        .root_source_file = b.path("src/sim.zig"),
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
    data_gen.root_module.addImport("haversine", haversine);
    b.installArtifact(data_gen);

    const data_gen_cmd = b.addRunArtifact(data_gen);
    data_gen_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        data_gen_cmd.addArgs(args);
    }
    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Steps -----------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const sim_step = b.step("sim", "Run the simulation application");
    sim_step.dependOn(&sim_cmd.step);

    const data_gen_step = b.step("data-gen", "Generate haversine data");
    data_gen_step.dependOn(&data_gen_cmd.step);

    // --------------------------------------------------------------------------------------------------------------
    // -------------------------------------------- Tests -----------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------
    const utils_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/utils/utils.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    const sim_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_unit_tests.root_module.addImport("sim8086", sim8086);

    const run_sim_unit_tests = b.addRunArtifact(sim_unit_tests);
    run_sim_unit_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_utils_unit_tests.step);
    test_step.dependOn(&run_sim8086_unit_tests.step);
    test_step.dependOn(&run_sim_unit_tests.step);
}
