const std = @import("std");
const log = std.log.scoped(.x86_64_multiboot);

/// Multiboot2 header magic number.
pub const MULTIBOOT2_MAGIC: u32 = 0xE85250D6;

/// Multiboot2 architecture (0 = i386, 1 = AMD64).
pub const MULTIBOOT2_ARCHITECTURE_AMD64: u32 = 1;

/// Multiboot2 header length.
pub const MULTIBOOT2_HEADER_LENGTH: u32 = 32;

/// Multiboot2 checksum.
pub const MULTIBOOT2_CHECKSUM: u32 = -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCHITECTURE_AMD64 + MULTIBOOT2_HEADER_LENGTH);

/// Multiboot2 header structure.
pub const Multiboot2Header = extern struct {
    /// Magic number.
    magic: u32,
    /// Architecture (0 = i386, 1 = AMD64).
    architecture: u32,
    /// Header length.
    header_length: u32,
    /// Checksum.
    checksum: u32,
};

/// Multiboot2 information structure.
pub const Multiboot2Info = extern struct {
    /// Total size of the structure.
    total_size: u32,
    /// Reserved (must be 0).
    reserved: u32,
};

/// Multiboot2 tag types.
pub const TagType = enum(u32) {
    end = 0,
    boot_loader_name = 1,
    module = 3,
    basic_meminfo = 4,
    bios_boot_device = 5,
    memory_map = 6,
    vbe_info = 7,
    framebuffer_info = 8,
    elf_sections = 9,
    apm_table = 10,
    efi_bs = 11,
    efi_32 = 12,
    efi_64 = 13,
    smbios = 14,
    acpi_old = 15,
    acpi_new = 16,
    networking_info = 17,
    efi_mmap = 18,
    efi_bs_not_supported = 19,
    efi_entry_point = 20,
    module_aligned = 21,
};

/// Multiboot2 tag header.
pub const Multiboot2Tag = extern struct {
    /// Tag type.
    type: u32,
    /// Tag size (including header).
    size: u32,
};

/// Memory map entry types.
pub const MemoryMapEntryType = enum(u32) {
    available = 1,
    reserved = 2,
    acpi_reclaimable = 3,
    acpi_nvs = 4,
    bad_memory = 5,
};

/// Memory map entry structure.
pub const MemoryMapEntry = extern struct {
    /// Base address (lower 32 bits).
    base_addr_low: u32,
    /// Base address (upper 32 bits).
    base_addr_high: u32,
    /// Length (lower 32 bits).
    length_low: u32,
    /// Length (upper 32 bits).
    length_high: u32,
    /// Type of memory region.
    type: u32,
    /// Reserved (must be 0).
    zero: u32,
    
    /// Get full 64-bit base address.
    pub fn baseAddr(self: *const MemoryMapEntry) u64 {
        return (@as(u64, self.base_addr_high) << 32) | self.base_addr_low;
    }
    
    /// Get full 64-bit length.
    pub fn length(self: *const MemoryMapEntry) u64 {
        return (@as(u64, self.length_high) << 32) | self.length_low;
    }
};

/// Module tag structure.
pub const ModuleTag = extern struct {
    /// Tag header.
    header: Multiboot2Tag,
    /// Module start address (lower 32 bits).
    mod_start_low: u32,
    /// Module start address (upper 32 bits).
    mod_start_high: u32,
    /// Module end address (lower 32 bits).
    mod_end_low: u32,
    /// Module end address (upper 32 bits).
    mod_end_high: u32,
    /// Module command line string.
    cmdline: [1]u8,
    
    /// Get full 64-bit start address.
    pub fn modStart(self: *const ModuleTag) u64 {
        return (@as(u64, self.mod_start_high) << 32) | self.mod_start_low;
    }
    
    /// Get full 64-bit end address.
    pub fn modEnd(self: *const ModuleTag) u64 {
        return (@as(u64, self.mod_end_high) << 32) | self.mod_end_low;
    }
};

/// Iterate over multiboot2 tags.
pub fn findTag(info: *const Multiboot2Info, comptime T: type, wanted_type: TagType) ?*T {
    var current_tag = @intToPtr([*]u8, @ptrToInt(info) + @sizeOf(Multiboot2Info));
    const end_ptr = @intToPtr([*]u8, @ptrToInt(info) + info.total_size);
    
    while (current_tag < end_ptr) {
        const tag = @intToPtr(*Multiboot2Tag, current_tag);
        
        if (tag.type == 0) break; // End tag
        
        if (tag.type == @intFromEnum(wanted_type)) {
            return @intToPtr(*T, current_tag);
        }
        
        // Align to 8 bytes
        const next_offset = (tag.size + 7) & @as(usize, ~@as(usize, 7));
        current_tag += next_offset;
    }
    
    return null;
}

test "multiboot2 structures" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Multiboot2Header));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Multiboot2Info));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Multiboot2Tag));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(MemoryMapEntry));
}
