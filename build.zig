const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zemplate = b.dependency("zemplate", .{});
    const mime = b.dependency("mime", .{});
    const zdotenv = b.dependency("zdotenv", .{});
    const tls = b.dependency("tls", .{});

    const exe = b.addExecutable(.{
        .name = "zortfolio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("zemplate", zemplate.module("zemplate"));
    exe.root_module.addImport("mime", mime.module("mime"));
    exe.root_module.addImport("tls", tls.module("tls"));
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
    exe_unit_tests.root_module.addImport("tls", tls.module("tls"));
    exe_unit_tests.root_module.addImport("zemplate", zemplate.module("zemplate"));
    exe_unit_tests.root_module.addImport("mime", mime.module("mime"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
