const std = @import("std");
const log = std.log.scoped(.x86_64_isr);
const arch = @import("arch.zig");
const idt = @import("idt.zig");

/// Exception handler function type.
pub const ExceptionHandler = fn (*arch.CpuState) void;

/// Number of exceptions (0-31).
const NUM_EXCEPTIONS: usize = 32;

/// Array of exception handlers.
var exception_handlers: [NUM_EXCEPTIONS]?ExceptionHandler = [_]?ExceptionHandler{null} ** NUM_EXCEPTIONS;

/// Register an exception handler.
pub fn registerHandler(int_num: u8, handler: ExceptionHandler) !void {
    if (int_num >= NUM_EXCEPTIONS) {
        return error.InvalidInterruptNumber;
    }
    exception_handlers[int_num] = handler;
}

/// Default exception handler.
fn defaultHandler(state: *arch.CpuState) void {
    const exception_names = [_][]const u8{
        "Division By Zero",
        "Debug",
        "Non Maskable Interrupt",
        "Breakpoint",
        "Overflow",
        "Bound Range Exceeded",
        "Invalid Opcode",
        "Device Not Available",
        "Double Fault",
        "Coprocessor Segment Overrun",
        "Invalid TSS",
        "Segment Not Present",
        "Stack-Segment Fault",
        "General Protection Fault",
        "Page Fault",
        "Reserved",
        "x87 FPU Error",
        "Alignment Check",
        "Machine Check",
        "SIMD FPU Exception",
        "Virtualization Exception",
        "Control Protection Exception",
        "Reserved",
        "Reserved",
        "Reserved",
        "Reserved",
        "Reserved",
        "Reserved",
        "Reserved",
        "Hypervisor Injection Exception",
        "VMM Communication Exception",
        "Security Exception",
        "Reserved",
    };

    const name = if (state.int_num < exception_names.len) exception_names[state.int_num] else "Unknown";
    
    log.err("\\n!!! EXCEPTION: {} (#{}) !!!\\n", .{ name, state.int_num });
    log.err("RIP: 0x{X}, RSP: 0x{X}, RFLAGS: 0x{X}\\n", .{ state.rip, state.rsp, state.rflags });
    log.err("Error Code: 0x{X}\\n", .{state.error_code});
    log.err("RAX: 0x{X}, RBX: 0x{X}, RCX: 0x{X}, RDX: 0x{X}\\n", .{ state.rax, state.rbx, state.rcx, state.rdx });
    log.err("RSI: 0x{X}, RDI: 0x{X}, RBP: 0x{X}, R8: 0x{X}\\n", .{ state.rsi, state.rdi, state.rbp, state.r8 });
    log.err("R9: 0x{X}, R10: 0x{X}, R11: 0x{X}, R12: 0x{X}\\n", .{ state.r9, state.r10, state.r11, state.r12 });
    log.err("R13: 0x{X}, R14: 0x{X}, R15: 0x{X}\\n", .{ state.r13, state.r14, state.r15 });
    
    arch.haltNoInterrupts();
}

/// Initialize ISR subsystem.
pub fn init() void {
    log.info("Init\\n", .{});
    defer log.info("Done\\n", .{});
    
    // Set default handlers for all exceptions
    for (exception_handlers) |*handler| {
        handler.* = defaultHandler;
    }
}

/// Main exception entry point (called from assembly stub).
pub fn handleException(state: *arch.CpuState) void {
    if (exception_handlers[state.int_num]) |handler| {
        handler(state);
    } else {
        defaultHandler(state);
    }
}

test "ISR initialization" {
    init();
    try std.testing.expect(exception_handlers[0] != null);
}
