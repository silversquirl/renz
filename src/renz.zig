const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw/main.zig");
const vk = @import("vk.zig");

pub const version = std.SemanticVersion.parse("0.1.0") catch unreachable;

// This is the allocator used for temporary allocation of buffers to receive data from Vulkan
// TODO: allow configuring this
const allocator = std.heap.c_allocator;

pub const Context = struct {
    d: vk.InstanceDispatch,
    inst: vk.Instance,

    pub const InitOptions = struct {
        app_name: ?[*:0]const u8 = null,
        app_version: u32 = 0,

        /// Whether to enable VK_LAYER_KHR_validation
        enable_validation: bool = builtin.mode == .Debug,
    };

    pub fn init(opts: InitOptions) !Context {
        try glfwInit();
        errdefer glfwTerminate();

        const d_base = try vk.BaseDispatch.load(
            @ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress),
        );

        const khr_validation = "VK_LAYER_KHR_validation";
        const layers: []const [*:0]const u8 =
            if (opts.enable_validation and try hasLayer(d_base, khr_validation))
            &.{khr_validation}
        else
            &.{};
        const exts = try glfw.getRequiredInstanceExtensions();

        const inst = try d_base.createInstance(.{
            .flags = .{},
            .p_application_info = &.{
                .p_application_name = opts.app_name,
                .application_version = opts.app_version,
                .p_engine_name = "renz",
                .engine_version = (version.major * 1000 + version.minor) * 1000 + version.patch,
                .api_version = vk.API_VERSION_1_0,
            },

            .enabled_layer_count = @intCast(u32, layers.len),
            .pp_enabled_layer_names = layers.ptr,

            .enabled_extension_count = @intCast(u32, exts.len),
            .pp_enabled_extension_names = exts.ptr,
        }, null);
        const d_inst = try vk.InstanceDispatch.load(inst, d_base.dispatch.vkGetInstanceProcAddr);
        errdefer d_inst.destroyInstance(inst, null);

        return Context{ .d = d_inst, .inst = inst };
    }

    pub fn deinit(self: Context) void {
        self.d.destroyInstance(self.inst, null);
        glfwTerminate();
    }

    var glfw_refcount: u32 = 0;
    fn glfwInit() !void {
        if (glfw_refcount == 0) {
            try glfw.init();
        }
        glfw_refcount += 1;
    }
    fn glfwTerminate() void {
        glfw_refcount -= 1;
        if (glfw_refcount == 0) {
            glfw.terminate();
        }
    }

    fn hasLayer(d_base: vk.BaseDispatch, name: []const u8) !bool {
        var layer_count: u32 = undefined;
        _ = try d_base.enumerateInstanceLayerProperties(&layer_count, null);
        const layers = try allocator.alloc(vk.LayerProperties, layer_count);
        defer allocator.free(layers);
        _ = try d_base.enumerateInstanceLayerProperties(&layer_count, layers.ptr);

        for (layers[0..layer_count]) |supported| {
            if (std.mem.eql(u8, name, std.mem.sliceTo(&supported.layer_name, 0))) {
                return true;
            }
        }
        return false;
    }

    pub fn pollEvents(_: Context) !void {
        try glfw.pollEvents();
    }
};

pub const Window = struct {
    win: glfw.Window,
    ctx: *const Context,

    d: vk.DeviceDispatch,
    dev: vk.Device,
    pdev: PhysicalDevice,

    graphics_pool: vk.CommandPool,
    compute_pool: vk.CommandPool,

    surface: vk.SurfaceKHR,
    format: vk.SurfaceFormatKHR,
    swapchain: vk.SwapchainKHR,
    size: vk.Extent2D,

    pub const InitOptions = struct {
        title: [*:0]const u8,
        width: u32,
        height: u32,
    };

    pub fn init(ctx: *const Context, opts: InitOptions) !Window {
        var self: Window = undefined;
        self.ctx = ctx;

        try glfw.Window.hint(.client_api, glfw.no_api);
        self.win = try glfw.Window.create(opts.width, opts.height, opts.title, null, null);
        errdefer self.win.destroy();

        self.pdev = try PhysicalDevice.init(ctx);

        const queue_infos = if (self.pdev.graphics_family == self.pdev.compute_family)
            &[_]vk.DeviceQueueCreateInfo{.{
                .flags = .{},
                .queue_family_index = self.pdev.graphics_family,
                .queue_count = 1,
                .p_queue_priorities = &[1]f32{1.0},
            }}
        else
            &[_]vk.DeviceQueueCreateInfo{ .{
                .flags = .{},
                .queue_family_index = self.pdev.graphics_family,
                .queue_count = 1,
                .p_queue_priorities = &[1]f32{1.0},
            }, .{
                .flags = .{},
                .queue_family_index = self.pdev.compute_family,
                .queue_count = 1,
                .p_queue_priorities = &[1]f32{1.0},
            } };

        self.dev = try ctx.d.createDevice(self.pdev.pdev, .{
            .flags = .{},

            .queue_create_info_count = @intCast(u32, queue_infos.len),
            .p_queue_create_infos = queue_infos.ptr,

            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,

            .enabled_extension_count = 1,
            .pp_enabled_extension_names = &[1][*:0]const u8{
                vk.extension_info.khr_swapchain.name,
            },

            .p_enabled_features = null,
        }, null);
        self.d = try vk.DeviceDispatch.load(self.dev, ctx.d.dispatch.vkGetDeviceProcAddr);
        errdefer self.d.destroyDevice(self.dev, null);

        self.graphics_pool = try self.d.createCommandPool(self.dev, .{
            .flags = .{ .transient_bit = true },
            .queue_family_index = self.pdev.graphics_family,
        }, null);
        errdefer self.d.destroyCommandPool(self.dev, self.graphics_pool, null);

        self.compute_pool = try self.d.createCommandPool(self.dev, .{
            .flags = .{ .transient_bit = true },
            .queue_family_index = self.pdev.compute_family,
        }, null);
        errdefer self.d.destroyCommandPool(self.dev, self.compute_pool, null);

        const result = try glfw.createWindowSurface(ctx.inst, self.win, null, &self.surface);
        switch (@intToEnum(vk.Result, result)) {
            .success => {},
            .error_out_of_host_memory => return error.OutOfHostMemory,
            .error_out_of_device_memory => return error.OutOfDeviceMemory,
            else => return error.Unknown,
        }
        errdefer ctx.d.destroySurfaceKHR(ctx.inst, self.surface, null);

        var count: u32 = 1;
        var formats: [1]vk.SurfaceFormatKHR = undefined;
        _ = try self.ctx.d.getPhysicalDeviceSurfaceFormatsKHR(self.pdev.pdev, self.surface, &count, &formats);
        self.format = formats[0];
        self.swapchain = .null_handle;
        try self.initSwapchain();

        return self;
    }

    pub fn deinit(self: Window) void {
        self.d.destroySwapchainKHR(self.dev, self.swapchain, null);
        self.ctx.d.destroySurfaceKHR(self.ctx.inst, self.surface, null);
        self.d.destroyDevice(self.dev, null);
        self.win.destroy();
    }

    fn initSwapchain(self: *Window) !void {
        const win_size = try self.win.getFramebufferSize();
        self.size = .{
            .width = @intCast(u32, win_size.width),
            .height = @intCast(u32, win_size.height),
        };

        // Create a new swapchain
        const result = self.d.createSwapchainKHR(self.dev, .{
            .flags = .{},
            .surface = self.surface,
            .min_image_count = 2,

            .image_format = self.format.format,
            .image_color_space = self.format.color_space,
            .image_extent = self.size,
            .image_array_layers = 1,

            .image_usage = .{
                .color_attachment_bit = true,
                .depth_stencil_attachment_bit = true,
            },
            .image_sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,

            .pre_transform = .{ .identity_bit_khr = true },
            .composite_alpha = .{ .opaque_bit_khr = true },

            .present_mode = .mailbox_khr,
            .clipped = vk.TRUE,
            .old_swapchain = self.swapchain,
        }, null);

        // Delete the old one
        if (self.swapchain != .null_handle) {
            self.d.destroySwapchainKHR(self.dev, self.swapchain, null);
        }

        // Handle errors
        self.swapchain = result catch .null_handle;
        _ = try result;
    }

    pub fn shouldClose(self: Window) bool {
        return self.win.shouldClose();
    }
};

pub const PhysicalDevice = struct {
    pdev: vk.PhysicalDevice,
    graphics_family: u32,
    compute_family: u32,

    pub fn init(ctx: *const Context) !PhysicalDevice {
        var n_devices: u32 = undefined;
        _ = try ctx.d.enumeratePhysicalDevices(ctx.inst, &n_devices, null);
        const devices = try allocator.alloc(vk.PhysicalDevice, n_devices);
        defer allocator.free(devices);
        _ = try ctx.d.enumeratePhysicalDevices(ctx.inst, &n_devices, devices.ptr);

        var self: PhysicalDevice = undefined;
        for (devices[0..n_devices]) |dev| {
            // TODO: check limits
            // const props = ctx.d.getPhysicalDeviceProperties(dev);

            // Check queue family support
            var n_families: u32 = undefined;
            ctx.d.getPhysicalDeviceQueueFamilyProperties(dev, &n_families, null);
            const families = try allocator.alloc(vk.QueueFamilyProperties, n_families);
            defer allocator.free(families);
            ctx.d.getPhysicalDeviceQueueFamilyProperties(dev, &n_families, families.ptr);

            var graphics_family: ?u32 = null;
            var compute_family: ?u32 = null;
            for (families[0..n_families]) |family, i| {
                const idx = @intCast(u32, i);
                // Prefer the same family for both
                if (family.queue_flags.graphics_bit and family.queue_flags.compute_bit) {
                    graphics_family = idx;
                    compute_family = idx;
                    break;
                }
                // Otherwise, look for individual families
                if (family.queue_flags.graphics_bit and graphics_family == null) {
                    graphics_family = idx;
                }
                if (family.queue_flags.compute_bit and compute_family == null) {
                    compute_family = idx;
                }
                // Check if we've found all the families we need
                if (graphics_family != null and compute_family != null) {
                    break;
                }
            } else {
                continue;
            }

            // We've found a usable device, use it
            self.pdev = dev;
            self.graphics_family = graphics_family.?;
            self.compute_family = compute_family.?;
            break;
        } else {
            return error.NoUsableDevice;
        }

        return self;
    }
};
