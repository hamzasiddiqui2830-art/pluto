const arch = @import("arch.zig");
const syscalls = @import("syscalls.zig");
const irq = @import("irq.zig");
const idt = @import("idt.zig");

extern fn irqHandler(ctx: *arch.CpuState) usize;
extern fn isrHandler(ctx: *arch.CpuState) usize;

///
/// The main handler for all exceptions and interrupts. This will then go and call the correct
/// handler for an ISR or IRQ.
///
/// Arguments:
///     IN ctx: *arch.CpuState - Pointer to the exception context containing the contents
///                              of the registers at the time of a exception.
///
export fn handler(ctx: *arch.CpuState) usize {
    if (ctx.int_num < irq.IRQ_OFFSET or ctx.int_num == syscalls.INTERRUPT) {
        return isrHandler(ctx);
    } else {
        return irqHandler(ctx);
    }
}

///
/// The common assembly that all exceptions and interrupts will call.
///
export fn commonStub() linksection(".text") void {
    asm volatile (
        "pusha\n\t"
        "push\n\t"
        "push\n\t"
        "push\n\t"
        "push\n\t"
        "mov\n\t"
        "push\n\t"
        "mov\n\t"
        "mov\n\t"
        "mov\n\t"
        "mov\n\t"
        "mov\n\t"
        "mov\n\t"
        "push\n\t"
        "call\n\t"
        "mov\n\t"
    );

    // Pop off the new cr3 then check if it's the same as the previous cr3
    // If so don't change cr3 to avoid a TLB flush
    asm volatile (
        "pop\n\t"
        "mov\n\t"
        "cmp\n\t"
        "je\n\t"
        "mov\n\t"
        \\same_cr3:
        \\pop   %%gs
        \\pop   %%fs
        \\pop   %%es
        \\pop   %%ds
        \\popa
    );
    // The Tss.esp0 value is the stack pointer used when an interrupt occurs. This should be the current process' stack pointer
    // So skip the rest of the CpuState, set Tss.esp0 then un-skip the last few fields of the CpuState
    asm volatile (
        "add\n\t"
        \\.extern main_tss_entry
        "mov\n\t"
        "sub\n\t"
        "iret\n\t"
    );
}

///
/// Generate the function that is the entry point for each exception/interrupt. This will then be
/// used as the handler for the corresponding IDT entry.
///
/// Arguments:
///     IN interrupt_num: u32 - The interrupt number to generate the function for.
///
/// Return: idt.InterruptHandler
///     The stub function that is called for each interrupt/exception.
///
pub fn getInterruptStub(comptime interrupt_num: u32) idt.InterruptHandler {
    return struct {
        fn func() linksection(".text") void {
            asm volatile (
                \\ cli
            );

            // These interrupts don't push an error code onto the stack, so will push a zero.
            if (interrupt_num != 8 and !(interrupt_num >= 10 and interrupt_num <= 14) and interrupt_num != 17) {
                asm volatile (
                    \\ pushl $0
                );
            }

            asm volatile (
                "pushl\n\t"
                :
                : [nr] "n" (interrupt_num)
            );
        }
    }.func;
}
