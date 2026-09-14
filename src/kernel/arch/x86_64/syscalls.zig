const std = @import("std");
const log = std.log.scoped(.x86_64_syscalls);
const arch = @import("arch.zig");

/// Syscall handler function type.
pub const SyscallHandler = fn (u64, u64, u64, u64, u64, u64) callconv(.C) u64;

/// Maximum number of syscalls.
const MAX_SYSCALLS: usize = 256;

/// Array of syscall handlers.
var syscall_handlers: [MAX_SYSCALLS]?SyscallHandler = [_]?SyscallHandler{null} ** MAX_SYSCALLS;

/// Register a syscall handler.
pub fn registerHandler(syscall_num: u64, handler: SyscallHandler) !void {
    if (syscall_num >= MAX_SYSCALLS) {
        return error.InvalidSyscallNumber;
    }
    syscall_handlers[syscall_num] = handler;
}

/// Default syscall handler (returns error).
fn defaultHandler(_: u64, _: u64, _: u64, _: u64, _: u64, _: u64) callconv(.C) u64 {
    return @intCast(u64, -1); // Error
}

/// Initialize syscall subsystem.
pub fn init() void {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});
    
    // Set up syscall/sysret MSRs for fast system calls
    setupSyscallMsrs();
}

/// Set up SYSCALL/SYSRET MSRs.
fn setupSyscallMsrs() void {
    const STAR_MSR: u32 = 0xC0000081; // SYSCALL Target Address Register
    const LSTAR_MSR: u32 = 0xC0000082; // Long Mode SYSCALL Target Address
    const SFMASK_MSR: u32 = 0xC0000084; // SYSCALL Flag Mask
    
    // Write to STAR MSR (legacy syscall target, not used in long mode)
    wrmsr(STAR_MSR, 0);
    
    // Write the address of our syscall handler to LSTAR
    const handler_addr = @intFromPtr(syscallEntry);
    wrmsr(LSTAR_MSR, handler_addr);
    
    // Set SFMASK to mask interrupts during syscall
    wrmsr(SFMASK_MSR, 0x200); // Mask IF flag
}

/// Write to Model Specific Register.
fn wrmsr(msr: u32, value: u64) void {
    const low = @truncate("{eax}" (low),
          "{edx}" (high),
        : "memory"
    );
}

/// Read from Model Specific Register.
fn rdmsr(msr: u32) u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile ("rdmsr"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        : "{ecx}" (msr),
    );
    return (@as(u64, high) << 32) | low;
}

/// Syscall entry point (called by SYSCALL instruction).
fn syscallEntry() noreturn {
    // Save registers on stack (handled by assembly stub)
    // In a real implementation, this would be assembly that:
    // 1. Saves user registers
    // 2. Extracts syscall number from RAX
    // 3. Calls the appropriate handler
    // 4. Returns result in RAX
    // 5. Executes SYSRET
    
    // For now, just halt
    arch.haltNoInterrupts();
}

/// Handle a syscall (called from assembly).
pub fn handleSyscall(syscall_num: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64) u64 {
    if (syscall_handlers[syscall_num]) |handler| {
        return handler(arg1, arg2, arg3, arg4, arg5, 0);
    }
    return defaultHandler(syscall_num, arg1, arg2, arg3, arg4, arg5);
}

test "syscall initialization" {
    init();
}
