const std = @import("std");
const log = std.log.scoped(.x86_64_serial);
const arch = @import("arch.zig");

/// Serial port base addresses.
pub const COM1_BASE: u16 = 0x3F8;
pub const COM2_BASE: u16 = 0x2F8;
pub const COM3_BASE: u16 = 0x3E8;
pub const COM4_BASE: u16 = 0x2E8;

/// Default baud rate.
pub const DEFAULT_BAUDRATE: u32 = 115200;

/// Serial port offsets.
const OFFSET_RX: u16 = 0;
const OFFSET_TX: u16 = 0;
const OFFSET_IER: u16 = 1;
const OFFSET_FCR: u16 = 2;
const OFFSET_LCR: u16 = 3;
const OFFSET_MCR: u16 = 4;
const OFFSET_LSR: u16 = 5;

/// Line status register bits.
const LSR_DATA_READY: u8 = 0x01;
const LSR_THR_EMPTY: u8 = 0x20;

/// Initialize a serial port.
pub fn init(baudrate: u32, base: u16) !void {
    log.info("Init (COM{d}, {d} baud)\\n", .{ ((base - COM1_BASE) / 0x100) + 1, baudrate });
    defer log.info("Done\\n", .{});
    
    // Disable interrupts
    arch.out(base + OFFSET_IER, 0x00);
    
    // Enable DLAB (set baud rate divisor)
    arch.out(base + OFFSET_LCR, 0x80);
    
    // Set divisor for baud rate
    const divisor = 115200 / baudrate;
    arch.out(base + OFFSET_RX, @truncate(u8, divisor));
    arch.out(base + OFFSET_IER, @truncate(u8, divisor >> 8));
    
    // Clear DLAB, set 8N1
    arch.out(base + OFFSET_LCR, 0x03);
    
    // Enable FIFO
    arch.out(base + OFFSET_FCR, 0xC7);
    
    // Enable interrupts, RTS/DSR
    arch.out(base + OFFSET_MCR, 0x0B);
}

/// Check if data is available to read.
pub fn canRead(base: u16) bool {
    return (arch.in(u8, base + OFFSET_LSR) & LSR_DATA_READY) != 0;
}

/// Read a byte from the serial port.
pub fn read(base: u16) ?u8 {
    if (!canRead(base)) {
        return null;
    }
    return arch.in(u8, base + OFFSET_RX);
}

/// Check if we can write to the serial port.
pub fn canWrite(base: u16) bool {
    return (arch.in(u8, base + OFFSET_LSR) & LSR_THR_EMPTY) != 0;
}

/// Write a byte to the serial port.
pub fn write(byte: u8, base: u16) void {
    while (!canWrite(base)) {}
    arch.out(base + OFFSET_TX, byte);
}

test "serial initialization" {
    // Test with COM1
    try init(DEFAULT_BAUDRATE, COM1_BASE);
}
