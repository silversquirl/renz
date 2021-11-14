const vk = @import("gen/vk.zig");
pub usingnamespace vk;

pub const BaseDispatch = vk.BaseWrapper(.{
    .CreateInstance,
    .EnumerateInstanceLayerProperties,
    .GetInstanceProcAddr,
});

pub const InstanceDispatch = vk.InstanceWrapper(.{
    .CreateDevice,
    .DestroyInstance,
    .DestroySurfaceKHR,

    .EnumeratePhysicalDevices,
    .GetDeviceProcAddr,
    .GetPhysicalDeviceQueueFamilyProperties,
    .GetPhysicalDeviceSurfaceFormatsKHR,
});

pub const DeviceDispatch = vk.DeviceWrapper(.{
    .CreateCommandPool,
    .CreateShaderModule,
    .CreateSwapchainKHR,

    .DestroyCommandPool,
    .DestroyDevice,
    .DestroyShaderModule,
    .DestroySwapchainKHR,
});
