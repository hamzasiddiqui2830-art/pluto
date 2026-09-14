const std = @import("std");
const log = std.log.scoped(.x86_64_irq);
const arch = @import("arch.zig");
const idt = @import("idt.zig");

/// IRQ handler function type.
pub const IrqHandler = fn (*arch.CpuState) void;

/// Number of IRQs (0-15 for legacy PIC).
const NUM_IRQS: usize = 16;

/// Array of IRQ handlers.
var irq_handlers: [NUM_IRQS]?IrqHandler = [_]?IrqHandler{null} ** NUM_IRQS;

/// Register an IRQ handler.
pub fn registerHandler(irq_num: u8, handler: IrqHandler) !void {
    if (irq_num >= NUM_IRQS) {
        return error.InvalidIrqNumber;
    }
    irq_handlers[irq_num] = handler;
}

/// Default IRQ handler (does nothing).
fn defaultHandler(state: *arch.CpuState) void {
    _ = state;
    // Acknowledge the interrupt in the IO-APIC or PIC
    // For now, just return
}

/// Initialize IRQ subsystem.
pub fn init() void {
    log.info("Init\\n", .{});
    defer log.info("Done\\n", .{});
    
    // Set default handlers for all IRQs
    for (irq_handlers) |*handler| {
        handler.* = defaultHandler;
    }
    
    // Remap IRQs if using PIC (for legacy compatibility)
    // In x86_64 long mode, typically use IO-APIC instead
    remapPic();
}

/// Remap legacy PIC to different interrupts.
fn remapPic() void {
    const PIC1_COMMAND: u16 = 0x20;
    const PIC1_DATA: u16 = 0x21;
    const PIC2_COMMAND: u16 = 0xA0;
    const PIC2_DATA: u16 = 0xA1;
    
    const ICW1_INIT: u8 = 0x11;
    const ICW4_8086: u8 = 0x01;
    
    // Start initialization sequence
    arch.out(PIC1_COMMAND, ICW1_INIT);
    arch.ioWait();
    arch.out(PIC2_COMMAND, ICW1_INIT);
    arch.ioWait();
    
    // Set vector offsets (IRQ 0-7 -> interrupts 32-39, IRQ 8-15 -> 40-47)
    arch.out(PIC1_DATA, 32);
    arch.ioWait();
    arch.out(PIC2_DATA, 40);
    arch.ioWait();
    
    // Tell Master PIC about Slave PIC
    arch.out(PIC1_DATA, 4);
    arch.ioWait();
    arch.out(PIC2_DATA, 2);
    arch.ioWait();
    
    // Set 8086 mode
    arch.out(PIC1_DATA, ICW4_8086);
    arch.ioWait();
    arch.out(PIC2_DATA, ICW4_8086);
    arch.ioWait();
    
    // Mask all interrupts initially
    arch.out(PIC1_DATA, 0xFF);
    arch.out(PIC2_DATA, 0xFF);
}

/// Send End of Interrupt signal.
pub fn sendEoi(irq_num: u8) void {
    const PIC1_COMMAND: u16 = 0x20;
    const PIC2_COMMAND: u16 = 0xA0;
    const EOI: u8 = 0x20;
    
    if (irq_num >= 8) {
        arch.out(PIC2_COMMAND, EOI);
    }
    arch.out(PIC1_COMMAND, EOI);
}

/// Main IRQ entry point (called from assembly stub).
pub fn handleIrq(irq_num: u8, state: *arch.CpuState) void {
    if (irq_handlers[irq_num]) |handler| {
        handler(state);
    }
    sendEoi(irq_num);
}

test "IRQ initialization" {
    init();
    try std.testing.expect(irq_handlers[0] != null);
}
