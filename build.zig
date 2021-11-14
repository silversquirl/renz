const std = @import("std");
const glfw_build = @import("deps/mach-glfw/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const shader_dir = std.fs.path.join(
        b.allocator,
        &.{ b.build_root, "src", "shader" },
    ) catch unreachable;

    const shader_compile = b.addSystemCommand(&.{
        "glslc",
        "-c",
        "shader.vert",
        "shader.frag",
    });
    shader_compile.cwd = shader_dir;

    const shader_link = b.addSystemCommand(&.{
        "spirv-link",
        "shader.vert.spv",
        "shader.frag.spv",
        "-o",
        "shader.spv",
    });
    shader_link.cwd = shader_dir;
    shader_link.step.dependOn(&shader_compile.step);

    const exe = b.addExecutable("main", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.step.dependOn(&shader_compile.step);

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
