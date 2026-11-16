const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");

    // zmon-core: plain data and helpers. No OS calls, no nanoui.
    const core = b.addModule("zmon-core", .{
        .root_source_file = b.path("core/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "nanoui", .module = nanoui },
        .{ .name = "zmon-core", .module = core },
    };

    const exe = b.addExecutable(.{ .name = "zmon", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });
    // A window of its own on Windows, without a console window beside it.
    if (target.result.os.tag == .windows) exe.subsystem = .windows;
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run zmon (opens its window)").dependOn(&run.step);

    const test_core = b.addTest(.{ .root_module = core });
    // The views are rendered offscreen with ui.Tester: no window opens.
    const test_ui = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });
    const run_core = b.addRunArtifact(test_core);
    const run_ui = b.addRunArtifact(test_ui);
    b.step("test-core", "Test the shared data and helpers").dependOn(&run_core.step);
    b.step("test-ui", "Test the app and its pages").dependOn(&run_ui.step);
    const tests = b.step("test", "Run every test");
    tests.dependOn(&run_core.step);
    tests.dependOn(&run_ui.step);

    // `zig build check`: the formatting gate, then a full build.
    const fmt = b.addFmt(.{
        .paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("core"), b.path("src") },
        .check = true,
    });
    const check = b.step("check", "Check formatting and build everything");
    check.dependOn(&fmt.step);
    check.dependOn(&exe.step);
}
