const std = @import("std");
const log = std.log.scoped(.x86_64_gdt);
const builtin = @import("builtin");
const is_test = builtin.is_test;
const panic = @import("../../panic.zig").panic;

/// The access bits for a GDT entry in long mode.
const AccessBits = packed struct {
    /// Whether the segment has been accessed. Set by CPU.
    accessed: u1,
    /// For code segments: readable. For data segments: writable.
    read_write: u1,
    /// For code segments: conforming. For data segments: direction.
    direction_conforming: u1,
    /// When set, the segment can be executed (code segment).
    executable: u1,
    /// Should be set for code and data segments, not for TSS.
    descriptor: u1,
    /// Privilege level (0 = kernel, 3 = user).
    privilege: u2,
    /// Whether the segment is present.
    present: u1,
};

/// The flag bits for a GDT entry in long mode.
const FlagBits = packed struct {
    /// Reserved, must be zero.
    reserved_zero: u1,
    /// When set indicates 64-bit code segment.
    is_64_bit: u1,
    /// When set indicates 32-bit protected mode segment.
    is_32_bit: u1,
    /// Granularity: 1 = 4KB blocks, 0 = 1B blocks.
    granularity: u1,
};

/// GDT entry structure for x86_64 (16 bytes).
pub const GdtEntry = packed struct {
    /// Lower 16 bits of limit.
    limit_low: u16,
    /// Lower 24 bits of base.
    base_low: u24,
    /// Access byte.
    access: AccessBits,
    /// Upper 4 bits of limit + flags.
    limit_high: u4,
    /// Flags.
    flags: FlagBits,
    /// Upper 8 bits of base.
    base_high: u8,
};

/// TSS structure for x86_64 (104 bytes minimum, but we use extended version).
pub const Tss = packed struct {
    /// Reserved.
    reserved1: u32,
    /// Ring 0 stack pointer (low 32 bits).
    rsp0_low: u32,
    /// Ring 0 stack pointer (high 32 bits).
    rsp0_high: u32,
    /// Ring 1 stack pointer (not used).
    rsp1: u64,
    /// Ring 2 stack pointer (not used).
    rsp2: u64,
    /// Reserved.
    reserved2: u64,
    /// Interrupt Stack Table 1.
    ist1: u64,
    /// Interrupt Stack Table 2.
    ist2: u64,
    /// Interrupt Stack Table 3.
    ist3: u64,
    /// Interrupt Stack Table 4.
    ist4: u64,
    /// Interrupt Stack Table 5.
    ist5: u64,
    /// Interrupt Stack Table 6.
    ist6: u64,
    /// Interrupt Stack Table 7.
    ist7: u64,
    /// Reserved.
    reserved3: u64,
    /// Reserved.
    reserved4: u16,
    /// I/O map base offset.
    io_permissions_base_offset: u16,
};

/// GDT pointer structure.
pub const GdtPtr = packed struct {
    /// Size of GDT minus 1.
    limit: u16,
    /// Base address of GDT.
    base: u64,
};

/// Number of GDT entries.
const NUMBER_OF_ENTRIES: u16 = 0x06;

/// Indexes into the GDT.
const NULL_INDEX: u16 = 0x00;
const KERNEL_CODE_INDEX: u16 = 0x01;
const KERNEL_DATA_INDEX: u16 = 0x02;
const USER_CODE_INDEX: u16 = 0x03;
const USER_DATA_INDEX: u16 = 0x04;
const TSS_INDEX: u16 = 0x05;

/// Offsets into the GDT (index * 8 for 64-bit entries).
pub const NULL_OFFSET: u16 = 0x00;
pub const KERNEL_CODE_OFFSET: u16 = 0x08;
pub const KERNEL_DATA_OFFSET: u16 = 0x10;
pub const USER_CODE_OFFSET: u16 = 0x18;
pub const USER_DATA_OFFSET: u16 = 0x20;
pub const TSS_OFFSET: u16 = 0x28;

/// Access bits for different segment types.
const NULL_SEGMENT: AccessBits = AccessBits{
    .accessed = 0,
    .read_write = 0,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor = 0,
    .privilege = 0,
    .present = 0,
};

const KERNEL_SEGMENT_CODE: AccessBits = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor = 1,
    .privilege = 0,
    .present = 1,
};

const KERNEL_SEGMENT_DATA: AccessBits = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor = 1,
    .privilege = 0,
    .present = 1,
};

const USER_SEGMENT_CODE: AccessBits = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor = 1,
    .privilege = 3,
    .present = 1,
};

const USER_SEGMENT_DATA: AccessBits = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor = 1,
    .privilege = 3,
    .present = 1,
};

const TSS_SEGMENT: AccessBits = AccessBits{
    .accessed = 1,
    .read_write = 0,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor = 0,
    .privilege = 0,
    .present = 1,
};

/// Flag bits for different modes.
const NULL_FLAGS: FlagBits = FlagBits{
    .reserved_zero = 0,
    .is_64_bit = 0,
    .is_32_bit = 0,
    .granularity = 0,
};

const LONG_MODE_CODE: FlagBits = FlagBits{
    .reserved_zero = 0,
    .is_64_bit = 1,
    .is_32_bit = 0,
    .granularity = 1,
};

const PAGING_32_BIT: FlagBits = FlagBits{
    .reserved_zero = 0,
    .is_64_bit = 0,
    .is_32_bit = 1,
    .granularity = 1,
};

/// GDT entries array.
var gdt_entries: [NUMBER_OF_ENTRIES]GdtEntry = init: {
    var gdt_entries_temp: [NUMBER_OF_ENTRIES]GdtEntry = undefined;

    // Null descriptor
    gdt_entries_temp[0] = makeGdtEntry(0, 0, NULL_SEGMENT, NULL_FLAGS);

    // Kernel code descriptor (64-bit)
    gdt_entries_temp[1] = makeGdtEntry(0, 0, KERNEL_SEGMENT_CODE, LONG_MODE_CODE);

    // Kernel data descriptor
    gdt_entries_temp[2] = makeGdtEntry(0, 0xFFFFF, KERNEL_SEGMENT_DATA, PAGING_32_BIT);

    // User code descriptor (64-bit)
    gdt_entries_temp[3] = makeGdtEntry(0, 0, USER_SEGMENT_CODE, LONG_MODE_CODE);

    // User data descriptor
    gdt_entries_temp[4] = makeGdtEntry(0, 0xFFFFF, USER_SEGMENT_DATA, PAGING_32_BIT);

    // TSS descriptor (will be initialized at runtime)
    gdt_entries_temp[5] = makeGdtEntry(0, 0, NULL_SEGMENT, NULL_FLAGS);

    break :init gdt_entries_temp;
};

/// GDT pointer.
var gdt_ptr: GdtPtr = GdtPtr{
    .limit = @sizeOf(GdtEntry) * NUMBER_OF_ENTRIES - 1,
    .base = undefined,
};

/// Main TSS entry.
pub var main_tss_entry: Tss align(16) = init: {
    var tss_temp = std.mem.zeroes(Tss);
    break :init tss_temp;
};

/// Make a GDT entry.
fn makeGdtEntry(base: u64, limit: u32, access: AccessBits, flags: FlagBits) GdtEntry {
    return .{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base & 0xFFFFFF),
        .access = .{
            .accessed = access.accessed,
            .read_write = access.read_write,
            .direction_conforming = access.direction_conforming,
            .executable = access.executable,
            .descriptor = access.descriptor,
            .privilege = access.privilege,
            .present = access.present,
        },
        .limit_high = @truncate(limit >> 16),
        .flags = .{
            .reserved_zero = flags.reserved_zero,
            .is_64_bit = flags.is_64_bit,
            .is_32_bit = flags.is_32_bit,
            .granularity = flags.granularity,
        },
        .base_high = @truncate(base >> 24),
    };
}

/// Initialize the GDT.
pub fn init() void {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});

    // Initialize TSS descriptor
    const tss_base: u64 = @intFromPtr(&main_tss_entry);
    const tss_limit: u32 = @sizeOf(Tss) - 1;
    gdt_entries[TSS_INDEX] = makeGdtEntry(tss_base, tss_limit, TSS_SEGMENT, NULL_FLAGS);

    // Set GDT pointer base
    gdt_ptr.base = @intFromPtr(&gdt_entries[0]);

    // Load GDT (declared in arch.zig)
    const arch = @import("arch.zig");
    arch.lgdt(&gdt_ptr);

    // Load TSS
    arch.ltr(TSS_OFFSET);
}

test "GDT entry sizes" {
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(AccessBits));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(FlagBits));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(GdtEntry));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(Tss));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(GdtPtr));
}
