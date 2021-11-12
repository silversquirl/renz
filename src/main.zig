const std = @import("std");
const renz = @import("renz.zig");

pub fn main() !void {
    const ctx = try renz.Context.init(.{});
    defer ctx.deinit();

    const win = try renz.Window.init(&ctx, .{
        .title = "Hello, world!",
        .width = 800,
        .height = 600,
    });
    defer win.deinit();

    while (!win.shouldClose()) {
        try ctx.pollEvents();
    }
}
