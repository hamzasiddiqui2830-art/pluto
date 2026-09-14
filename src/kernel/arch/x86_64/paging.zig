const std = @import("std");
const log = std.log.scoped(.x86_64_paging);
const builtin = @import("builtin");
const is_test = builtin.is_test;
const panic = @import("../../panic.zig").panic;
const arch = if (builtin.is_test) @import("../../../../test/mock/kernel/arch_mock.zig") else @import("arch.zig");
const MemProfile = @import("../../mem.zig").MemProfile;

/// Page size constants.
pub const PAGE_SIZE_4KB: usize = 0x1000;
pub const PAGE_SIZE_2MB: usize = 0x200000;
pub const PAGE_SIZE_1GB: usize = 0x40000000;

/// Number of entries per level.
const ENTRIES_PER_LEVEL: usize = 512;

/// Bitmasks for PML4, PDPT, PD, and PT entries.
const ENTRY_PRESENT: u64 = 0x1;
const ENTRY_WRITABLE: u64 = 0x2;
const ENTRY_USER: u64 = 0x4;
const ENTRY_WRITE_THROUGH: u64 = 0x8;
const ENTRY_CACHE_DISABLED: u64 = 0x10;
const ENTRY_ACCESSED: u64 = 0x20;
const ENTRY_DIRTY: u64 = 0x40;
const ENTRY_LARGE_PAGE: u64 = 0x80;
const ENTRY_GLOBAL: u64 = 0x100;
const ENTRY_ADDR_MASK: u64 = 0x000FFFFFFFFFF000;

/// Page map level 4 entry.
pub const Pml4Entry = u64;

/// Page directory pointer table entry.
pub const PdptEntry = u64;

/// Page directory entry.
pub const PdEntry = u64;

/// Page table entry.
pub const PtEntry = u64;

/// PML4 table structure.
pub const Pml4Table = extern struct {
    entries: [ENTRIES_PER_LEVEL]Pml4Entry,
};

/// Page directory pointer table structure.
pub const PdptTable = extern struct {
    entries: [ENTRIES_PER_LEVEL]PdptEntry,
};

/// Page directory structure.
pub const PdTable = extern struct {
    entries: [ENTRIES_PER_LEVEL]PdEntry,
};

/// Page table structure.
pub const PtTable = extern struct {
    entries: [ENTRIES_PER_LEVEL]PtEntry,
};

/// Kernel's page map level 4 table.
pub var kernel_pml4: Pml4Table align(PAGE_SIZE_4KB) = .{
    .entries = [_]Pml4Entry{0} ** ENTRIES_PER_LEVEL,
};

/// Convert virtual address to PML4 index.
inline fn virtToPml4Idx(virt: usize) usize {
    return (virt >> 39) & 0x1FF;
}

/// Convert virtual address to PDPT index.
inline fn virtToPdptIdx(virt: usize) usize {
    return (virt >> 30) & 0x1FF;
}

/// Convert virtual address to PD index.
inline fn virtToPdIdx(virt: usize) usize {
    return (virt >> 21) & 0x1FF;
}

/// Convert virtual address to PT index.
inline fn virtToPtIdx(virt: usize) usize {
    return (virt >> 12) & 0x1FF;
}

/// Get the page offset from a virtual address.
inline fn virtToOffset(virt: usize) usize {
    return virt & 0xFFF;
}

/// Map a physical address to a virtual address in the given PML4 table.
pub fn map(pml4: *Pml4Table, virt: usize, phys: usize, flags: u64) !void {
    const pml4_idx = virtToPml4Idx(virt);
    const pdpt_idx = virtToPdptIdx(virt);
    const pd_idx = virtToPdIdx(virt);
    const pt_idx = virtToPtIdx(virt);
    
    // Check if PML4 entry exists
    if ((pml4.entries[pml4_idx] & ENTRY_PRESENT) == 0) {
        // Need to allocate PDPT - for now just return error
        // In real implementation, would allocate from physical memory manager
        return error.NoMemory;
    }
    
    const pdpt_addr = pml4.entries[pml4_idx] & ENTRY_ADDR_MASK;
    const pdpt = @ptrFromInt(*PdptTable, pdpt_addr);
    
    // Check if PDPT entry exists
    if ((pdpt.entries[pdpt_idx] & ENTRY_PRESENT) == 0) {
        return error.NoMemory;
    }
    
    const pd_addr = pdpt.entries[pdpt_idx] & ENTRY_ADDR_MASK;
    const pd = @ptrFromInt(*PdTable, pd_addr);
    
    // Check if PD entry exists
    if ((pd.entries[pd_idx] & ENTRY_PRESENT) == 0) {
        return error.NoMemory;
    }
    
    const pt_addr = pd.entries[pd_idx] & ENTRY_ADDR_MASK;
    const pt = @ptrFromInt(*PtTable, pt_addr);
    
    // Set up the page table entry
    pt.entries[pt_idx] = (phys & ENTRY_ADDR_MASK) | flags | ENTRY_PRESENT;
    
    // Flush TLB for this address
    flushTlb(virt);
}

/// Unmap a virtual address.
pub fn unmap(pml4: *Pml4Table, virt: usize) !void {
    const pml4_idx = virtToPml4Idx(virt);
    const pdpt_idx = virtToPdptIdx(virt);
    const pd_idx = virtToPdIdx(virt);
    const pt_idx = virtToPtIdx(virt);
    
    if ((pml4.entries[pml4_idx] & ENTRY_PRESENT) == 0) {
        return error.NotMapped;
    }
    
    const pdpt_addr = pml4.entries[pml4_idx] & ENTRY_ADDR_MASK;
    const pdpt = @ptrFromInt(*PdptTable, pdpt_addr);
    
    if ((pdpt.entries[pdpt_idx] & ENTRY_PRESENT) == 0) {
        return error.NotMapped;
    }
    
    const pd_addr = pdpt.entries[pdpt_idx] & ENTRY_ADDR_MASK;
    const pd = @ptrFromInt(*PdTable, pd_addr);
    
    if ((pd.entries[pd_idx] & ENTRY_PRESENT) == 0) {
        return error.NotMapped;
    }
    
    const pt_addr = pd.entries[pd_idx] & ENTRY_ADDR_MASK;
    const pt = @ptrFromInt(*PtTable, pt_addr);
    
    pt.entries[pt_idx] = 0;
    flushTlb(virt);
}

/// Flush TLB for a specific address.
fn flushTlb(virt: usize) void {
    asm volatile ("invlpg [%[addr]]" :: [addr] "r" (virt) : "memory");
}

/// Load CR3 with the physical address of the PML4 table.
pub fn loadCr3(pml4_phys: usize) void {
    asm volatile ("mov cr3, %[val]" :: [val] "r" (pml4_phys) : "memory");
}

/// Read CR3 register.
pub fn readCr3() usize {
    var val: usize = undefined;
    asm volatile ("mov %[val], cr3" : [val] "=r" (val));
    return val;
}

/// Initialize paging for x86_64.
pub fn init(mem_profile: *const MemProfile) void {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});
    
    // Clear the kernel PML4
    for (kernel_pml4.entries) |*entry| {
        entry.* = 0;
    }
    
    // Identity map the first 2MB for bootloader compatibility
    // This is a simplified setup - full implementation would map all physical memory
    
    // Load the kernel PML4
    const pml4_phys = mem.virtToPhys(@intFromPtr(&kernel_pml4));
    loadCr3(pml4_phys);
}

/// Switch to a different address space.
pub fn switchAddressSpace(pml4_phys: usize) void {
    loadCr3(pml4_phys);
}

test "paging sizes" {
    try std.testing.expectEqual(@as(usize, 4096), @sizeOf(Pml4Table));
    try std.testing.expectEqual(@as(usize, 4096), @sizeOf(PdptTable));
    try std.testing.expectEqual(@as(usize, 4096), @sizeOf(PdTable));
    try std.testing.expectEqual(@as(usize, 4096), @sizeOf(PtTable));
}
