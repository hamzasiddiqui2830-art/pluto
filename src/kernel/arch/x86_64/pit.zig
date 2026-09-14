const std = @import("std");
const log = std.log.scoped(.x86_64_pit);
const arch = @import("arch.zig");

/// PIT ports.
const PIT_CHANNEL0: u16 = 0x40;
const PIT_COMMAND: u16 = 0x43;

/// Default frequency (100 Hz).
pub const DEFAULT_FREQUENCY: u32 = 100;

/// PIT divisor for a given frequency.
fn pitDivisor(frequency: u32) u16 {
    const PIT_BASE_FREQ: u32 = 1193182;
    return @truncate(u16, PIT_BASE_FREQ / frequency);
}

/// Initialize the PIT timer.
pub fn init() void {
    log.info("Init\\n", .{});
    defer log.info("Done\\n", .{});
    
    setFrequency(DEFAULT_FREQUENCY);
}

/// Set the PIT frequency.
pub fn setFrequency(frequency: u32) void {
    const divisor = pitDivisor(frequency);
    
    // Send command byte: channel 0, lobyte/hibyte, square wave generator, binary
    arch.out(PIT_COMMAND, 0x36);
    
    // Send divisor
    arch.out(PIT_CHANNEL0, @truncate(u8, divisor));
    arch.out(PIT_CHANNEL0, @truncate(u8, divisor >> 8));
}

test "PIT initialization" {
    init();
}
