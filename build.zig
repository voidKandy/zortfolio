const std = @import("std");

fn loadDotEnv(run: *std.Build.Step.Run) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env_file = std.fs.cwd().openFile(".env", .{}) catch
        @panic("unable to open .env");

    defer env_file.close();

    const read_buffer = arena.alloc(u8, 2048) catch @panic("out of memory");
    var reader = env_file.reader(read_buffer);

    const contents = reader.interface.allocRemaining(arena, .unlimited) catch @panic("failed to read");

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var parts = std.mem.splitScalar(u8, trimmed, '=');

        const key = parts.first();
        const value = std.mem.trim(u8, parts.rest(), " \"");

        run.setEnvironmentVariable(key, value);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zemplate = b.dependency("zemplate", .{});
    const mime = b.dependency("mime", .{});
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

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    loadDotEnv(run_cmd);

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
    exe_unit_tests.root_module.addImport("tls", tls.module("tls"));
    exe_unit_tests.root_module.addImport("zemplate", zemplate.module("zemplate"));
    exe_unit_tests.root_module.addImport("mime", mime.module("mime"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
