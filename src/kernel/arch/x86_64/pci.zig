const std = @import("std");
const log = std.log.scoped(.x86_64_pci);
const Allocator = std.mem.Allocator;
const arch = @import("arch.zig");

/// PCI configuration space ports.
const PCI_CONFIG_ADDR: u16 = 0xCF8;
const PCI_CONFIG_DATA: u16 = 0xCFC;

/// PCI configuration address format.
fn makePciAddr(bus: u8, slot: u8, func: u8, offset: u8) u32 {
    return 0x80000000 | (@as(u32, bus) << 16) | (@as(u32, slot) << 11) | (@as(u32, func) << 8) | offset;
}

/// Read from PCI configuration space.
fn pciRead(addr: u32) u32 {
    arch.out(PCI_CONFIG_ADDR, addr);
    return arch.in(u32, PCI_CONFIG_DATA);
}

/// Write to PCI configuration space.
fn pciWrite(addr: u32, value: u32) void {
    arch.out(PCI_CONFIG_ADDR, addr);
    arch.out(PCI_CONFIG_DATA, value);
}

/// Get vendor ID from a PCI device.
fn getVendorId(bus: u8, slot: u8, func: u8) u16 {
    const addr = makePciAddr(bus, slot, func, 0);
    const value = pciRead(addr);
    return @truncate(value);
}

/// Get device ID from a PCI device.
fn getDeviceId(bus: u8, slot: u8, func: u8) u16 {
    const addr = makePciAddr(bus, slot, func, 0);
    const value = pciRead(addr);
    return @truncate(value >> 16);
}

/// Get class code from a PCI device.
fn getClassCode(bus: u8, slot: u8, func: u8) u8 {
    const addr = makePciAddr(bus, slot, func, 8);
    const value = pciRead(addr);
    return @truncate(value >> 24);
}

/// Get subclass from a PCI device.
fn getSubclass(bus: u8, slot: u8, func: u8) u8 {
    const addr = makePciAddr(bus, slot, func, 8);
    const value = pciRead(addr);
    return @truncate(value >> 16);
}

/// Get programming interface from a PCI device.
fn getProgIf(bus: u8, slot: u8, func: u8) u8 {
    const addr = makePciAddr(bus, slot, func, 8);
    const value = pciRead(addr);
    return @truncate(value >> 8);
}

/// Get BAR (Base Address Register) from a PCI device.
fn getBar(bus: u8, slot: u8, func: u8, bar_num: u8) u32 {
    const offset = 0x10 + (bar_num * 4);
    const addr = makePciAddr(bus, slot, func, offset);
    return pciRead(addr);
}

/// PCI device information structure.
pub const PciDeviceInfo = struct {
    bus: u8,
    slot: u8,
    func: u8,
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
    prog_if: u8,
    bars: [6]u32,
};

/// Enumerate all PCI devices.
pub fn getDevices(allocator: Allocator) Allocator.Error![]PciDeviceInfo {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});
    
    var devices = std.ArrayList(PciDeviceInfo).init(allocator);
    errdefer devices.deinit();
    
    // Scan all buses, slots, and functions
    for (0..8) |bus| {
        for (0..32) |slot| {
            for (0..8) |func| {
                const vendor_id = getVendorId(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8));
                
                // Skip invalid devices (vendor_id 0xFFFF means no device)
                if (vendor_id == 0xFFFF) {
                    // If func is 0 and we got an invalid device, there are no more functions
                    if (func == 0) break;
                    continue;
                }
                
                const device_info = PciDeviceInfo{
                    .bus = @intCast(bus, u8),
                    .slot = @intCast(slot, u8),
                    .func = @intCast(func, u8),
                    .vendor_id = vendor_id,
                    .device_id = getDeviceId(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8)),
                    .class_code = getClassCode(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8)),
                    .subclass = getSubclass(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8)),
                    .prog_if = getProgIf(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8)),
                    .bars = .{
                        getBar(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8), 0),
                        getBar(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8), 1),
                        getBar(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8), 2),
                        getBar(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8), 3),
                        getBar(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8), 4),
                        getBar(@intCast(bus, u8), @intCast(slot, u8), @intCast(func, u8), 5),
                    },
                };
                
                try devices.append(device_info);
            }
        }
    }
    
    return devices.toOwnedSlice();
}

test "PCI enumeration" {
    // Mock test - actual PCI enumeration requires hardware
}
