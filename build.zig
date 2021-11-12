const std = @import("std");
const glfw_build = @import("deps/mach-glfw/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("main", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    glfw_build.link(b, exe, .{
        .vulkan = true,
        .metal = false,
    });

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
