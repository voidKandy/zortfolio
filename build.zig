const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    const zemplate = b.dependency("zemplate", .{});
    const zdotenv = b.dependency("zdotenv", .{});

    const exe = b.addExecutable(.{
        .name = "zortfolio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("zap", zap.module("zap"));
    exe.root_module.addImport("zemplate", zemplate.module("zemplate"));
    exe.root_module.addImport("zdotenv", zdotenv.module("zdotenv"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe_unit_tests.root_module.addImport("zdotenv", zdotenv.module("zdotenv"));
    exe_unit_tests.root_module.addImport("zap", zap.module("zap"));
    exe_unit_tests.root_module.addImport("zemplate", zemplate.module("zemplate"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
