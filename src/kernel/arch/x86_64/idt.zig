const std = @import("std");
const log = std.log.scoped(.x86_64_idt);
const builtin = @import("builtin");
const is_test = builtin.is_test;
const panic = @import("../../panic.zig").panic;
const gdt = if (is_test) @import("../../../../test/mock/kernel/gdt_mock.zig") else @import("gdt.zig");
const arch = if (builtin.is_test) @import("../../../../test/mock/kernel/arch_mock.zig") else @import("arch.zig");

/// IDT entry structure for x86_64 (16 bytes).
pub const IdtEntry = packed struct {
    /// Lower 16 bits of handler offset.
    base_low: u16,
    /// Code segment selector.
    selector: u16,
    /// Interrupt Stack Table offset (bits 0-2), reserved (bits 3-7).
    ist: u8,
    /// Gate type and attributes.
    gate_type: u4,
    /// Reserved (must be 0).
    storage_segment: u1,
    /// Privilege level.
    privilege: u2,
    /// Present bit.
    present: u1,
    /// Middle 16 bits of handler offset.
    base_middle: u16,
    /// Upper 32 bits of handler offset.
    base_high: u32,
    /// Reserved.
    zero: u32,
};

/// IDT pointer structure.
pub const IdtPtr = packed struct {
    /// Size of IDT minus 1.
    limit: u16,
    /// Base address of IDT.
    base: u64,
};

/// Interrupt handler function type.
pub const InterruptHandler = fn () linksection(".text") void;

/// IDT error types.
pub const IdtError = error{
    /// IDT entry already exists.
    IdtEntryExists,
};

/// Gate types.
const TASK_GATE: u4 = 0x5;
const INTERRUPT_GATE: u4 = 0xE;
const TRAP_GATE: u4 = 0xF;

/// Privilege levels.
const PRIVILEGE_RING_0: u2 = 0x0;
const PRIVILEGE_RING_1: u2 = 0x1;
const PRIVILEGE_RING_2: u2 = 0x2;
const PRIVILEGE_RING_3: u2 = 0x3;

/// Number of IDT entries.
pub const NUMBER_OF_ENTRIES: u16 = 256;

/// IDT table size.
const TABLE_SIZE: u16 = @sizeOf(IdtEntry) * NUMBER_OF_ENTRIES - 1;

/// IDT pointer.
var idt_ptr: IdtPtr = IdtPtr{
    .limit = TABLE_SIZE,
    .base = 0,
};

/// IDT entries array.
var idt_entries: [NUMBER_OF_ENTRIES]IdtEntry = [_]IdtEntry{IdtEntry{
    .base_low = 0,
    .selector = 0,
    .ist = 0,
    .gate_type = 0,
    .storage_segment = 0,
    .privilege = 0,
    .present = 0,
    .base_middle = 0,
    .base_high = 0,
    .zero = 0,
}} ** NUMBER_OF_ENTRIES;

/// Make an IDT entry.
fn makeEntry(base: u64, selector: u16, gate_type: u4, privilege: u2, ist: u8) IdtEntry {
    return IdtEntry{
        .base_low = @truncate(base),
        .selector = selector,
        .ist = ist,
        .gate_type = gate_type,
        .storage_segment = 0,
        .privilege = privilege,
        .present = 1,
        .base_middle = @truncate(base >> 16),
        .base_high = @truncate(base >> 32),
        .zero = 0,
    };
}

/// Check if IDT entry is open (present).
pub fn isIdtOpen(entry: IdtEntry) bool {
    return entry.present == 1;
}

/// Open an interrupt gate.
pub fn openInterruptGate(index: u8, handler: InterruptHandler) IdtError!void {
    if (isIdtOpen(idt_entries[index])) {
        return IdtError.IdtEntryExists;
    }

    idt_entries[index] = makeEntry(@intFromPtr(handler), gdt.KERNEL_CODE_OFFSET, INTERRUPT_GATE, PRIVILEGE_RING_0, 0);
}

/// Initialize the IDT.
pub fn init() void {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});

    idt_ptr.base = @intFromPtr(&idt_entries);
    arch.lidt(&idt_ptr);
}

test "IDT entry sizes" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(IdtEntry));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(IdtPtr));
}
