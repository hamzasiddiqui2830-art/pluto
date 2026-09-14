const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.x86_64_arch);
const builtin = @import("builtin");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const paging = @import("paging.zig");
const mem = @import("../../mem.zig");
const vmm = @import("../../vmm.zig");
const Task = @import("../../task.zig").Task;
const Serial = @import("../../serial.zig").Serial;
const panic = @import("../../panic.zig").panic;
const TTY = @import("../../tty.zig").TTY;
const Keyboard = @import("../../keyboard.zig").Keyboard;
const MemProfile = mem.MemProfile;

/// Device type (placeholder for now).
pub const Device = struct {
    vendor_id: u16,
    device_id: u16,
};

/// Date/time structure (placeholder).
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Virtual end of kernel code.
extern var KERNEL_VADDR_END: *u8;

/// Virtual start of kernel code.
extern var KERNEL_VADDR_START: *u8;

/// Physical end of kernel code.
extern var KERNEL_PHYSADDR_END: *u8;

/// Physical start of kernel code.
extern var KERNEL_PHYSADDR_START: *u8;

/// Boot-time offset between virtual and physical addresses.
extern var KERNEL_ADDR_OFFSET: *u8;

/// Virtual address of stack top.
extern var KERNEL_STACK_START: *u8;

/// Virtual address of stack bottom.
extern var KERNEL_STACK_END: *u8;

/// CPU state structure for x86_64 (saved on interrupt/exception).
pub const CpuState = packed struct {
    // General purpose registers (64-bit)
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,

    // Interrupt number and error code
    int_num: u64,
    error_code: u64,

    // Instruction pointer and flags
    rip: u64,
    cs: u64,
    rflags: u64,

    // Stack pointer
    rsp: u64,

    // Segment selectors (for user mode transitions)
    ss: u64,
    fs: u64,
    gs: u64,

    pub fn empty() CpuState {
        return .{
            .rax = undefined,
            .rbx = undefined,
            .rcx = undefined,
            .rdx = undefined,
            .rsi = undefined,
            .rdi = undefined,
            .rbp = undefined,
            .r8 = undefined,
            .r9 = undefined,
            .r10 = undefined,
            .r11 = undefined,
            .r12 = undefined,
            .r13 = undefined,
            .r14 = undefined,
            .r15 = undefined,
            .int_num = undefined,
            .error_code = undefined,
            .rip = undefined,
            .cs = undefined,
            .rflags = undefined,
            .rsp = undefined,
            .ss = undefined,
            .fs = undefined,
            .gs = undefined,
        };
    }
};

/// Boot payload type (multiboot info for now).
pub const BootPayload = ?*struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms: [4]u32,
    mmap_length: u32,
    mmap_addr: u32,
    drives_length: u32,
    drives_addr: u32,
    config_table: u32,
    boot_loader_name: u32,
    apm_table: u32,
};

/// VMM payload type (PML4 table).
pub const VmmPayload = *paging.Pml4Table;

/// Kernel's VMM payload.
pub const KERNEL_VMM_PAYLOAD = &paging.kernel_pml4;

/// VMM mapper functions.
pub const VMM_MAPPER: vmm.Mapper(VmmPayload) = vmm.Mapper(VmmPayload){
    .mapFn = map,
    .unmapFn = unmap,
};

/// Memory block size (page size).
pub const MEMORY_BLOCK_SIZE: usize = paging.PAGE_SIZE_4KB;

/// Map function for VMM.
fn map(payload: VmmPayload, virt: usize, phys: usize, flags: u64) !void {
    try paging.map(payload, virt, phys, flags);
}

/// Unmap function for VMM.
fn unmap(payload: VmmPayload, virt: usize) !void {
    try paging.unmap(payload, virt);
}

/// Read from I/O port.
pub fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u64 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        else => @compileError("Invalid data type. Only u8, u16, u32 or u64, found: " ++ @typeName(Type)),
    };
}

/// Write to I/O port.
pub fn out(port: u16, data: anytype) void {
    switch (@TypeOf(data)) {
        u8 => asm volatile ("outb %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{al}" (data),
        ),
        u16 => asm volatile ("outw %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{ax}" (data),
        ),
        u32 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data),
        ),
        u64 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data),
        ),
        else => @compileError("Invalid data type. Only u8, u16, u32 or u64, found: " ++ @typeName(@TypeOf(data))),
    }
}

/// I/O wait.
pub fn ioWait() void {
    out(0x80, @as(u8, 0));
}

/// Load GDT.
pub fn lgdt(gdt_ptr: *const gdt.GdtPtr) void {
    asm volatile ("lgdt (%%rax)"
        :
        : [gdt_ptr] "{rax}" (gdt_ptr),
    );
}

/// Store GDT.
pub fn sgdt() gdt.GdtPtr {
    var gdt_ptr = gdt.GdtPtr{ .limit = 0, .base = 0 };
    asm volatile ("sgdt (%%rax)"
        : [gdt_ptr] "=m" (gdt_ptr),
    );
    return gdt_ptr;
}

/// Load TSS.
pub fn ltr(offset: u16) void {
    asm volatile ("ltr %%ax"
        :
        : [offset] "{ax}" (offset),
    );
}

/// Load IDT.
pub fn lidt(idt_ptr: *const idt.IdtPtr) void {
    asm volatile ("lidt (%%rax)"
        :
        : [idt_ptr] "{rax}" (idt_ptr),
    );
}

/// Store IDT.
pub fn sidt() idt.IdtPtr {
    var idt_ptr = idt.IdtPtr{ .limit = 0, .base = 0 };
    asm volatile ("sidt (%%rax)"
        : [idt_ptr] "=m" (idt_ptr),
    );
    return idt_ptr;
}

/// Enable interrupts.
pub fn enableInterrupts() void {
    asm volatile ("sti");
}

/// Disable interrupts.
pub fn disableInterrupts() void {
    asm volatile ("cli");
}

/// Halt CPU.
pub fn halt() void {
    asm volatile ("hlt");
}

/// Spin wait with interrupts enabled.
pub fn spinWait() noreturn {
    enableInterrupts();
    while (true) {
        halt();
    }
}

/// Halt without interrupts.
pub fn haltNoInterrupts() noreturn {
    while (true) {
        disableInterrupts();
        halt();
    }
}

/// Initialize serial.
pub fn initSerial(boot_payload: BootPayload) Serial {
    _ = boot_payload;
    // Placeholder - implement proper serial initialization
    return Serial{
        .write = writeSerialCom1,
    };
}

fn writeSerialCom1(byte: u8) void {
    // Simple serial write placeholder
    const SERIAL_PORT = 0x3F8;
    while ((in(u8, SERIAL_PORT + 5) & 0x20) == 0) {}
    out(SERIAL_PORT, byte);
}

/// Initialize TTY.
pub fn initTTY(boot_payload: BootPayload) TTY {
    _ = boot_payload;
    // Placeholder - implement proper VGA/text mode initialization
    return .{
        .print = stubPrint,
        .setCursor = stubSetCursor,
        .cols = 80,
        .rows = 25,
        .clear = stubClear,
    };
}

fn stubPrint(_: []const u8) void {}
fn stubSetCursor(_: u8, _: u8) void {}
fn stubClear() void {}

/// Initialize memory.
pub fn initMem(mb_info: BootPayload) Allocator.Error!MemProfile {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});

    const allocator = mem.fixed_buffer_allocator.allocator();
    var reserved_physical_mem = std.ArrayList(mem.Range).init(allocator);
    var reserved_virtual_mem = std.ArrayList(mem.Map).init(allocator);
    var modules = std.ArrayList(mem.Module).init(allocator);

    // Reserve kernel regions
    const kernel_virt = mem.Range{
        .start = @intFromPtr(&KERNEL_VADDR_START),
        .end = @intFromPtr(&KERNEL_STACK_START),
    };
    const kernel_phy = mem.Range{
        .start = mem.virtToPhys(kernel_virt.start),
        .end = mem.virtToPhys(kernel_virt.end),
    };
    try reserved_virtual_mem.append(.{
        .virtual = kernel_virt,
        .physical = kernel_phy,
    });

    // Map kernel stack
    const kernel_stack_virt = mem.Range{
        .start = @intFromPtr(&KERNEL_STACK_START),
        .end = @intFromPtr(&KERNEL_STACK_END),
    };
    const kernel_stack_phy = mem.Range{
        .start = mem.virtToPhys(kernel_stack_virt.start),
        .end = mem.virtToPhys(kernel_stack_virt.end),
    };
    try reserved_virtual_mem.append(.{
        .virtual = kernel_stack_virt,
        .physical = kernel_stack_phy,
    });

    return MemProfile{
        .vaddr_end = &KERNEL_VADDR_END,
        .vaddr_start = &KERNEL_VADDR_START,
        .physaddr_end = &KERNEL_PHYSADDR_END,
        .physaddr_start = &KERNEL_PHYSADDR_START,
        .mem_kb = if (mb_info) |info| info.mem_upper + info.mem_lower + 1024 else 0,
        .modules = modules.items,
        .physical_reserved = reserved_physical_mem.items,
        .virtual_reserved = reserved_virtual_mem.items,
        .fixed_allocator = mem.fixed_buffer_allocator,
    };
}

/// Initialize keyboard.
pub fn initKeyboard(allocator: Allocator) Allocator.Error!*Keyboard {
    _ = allocator;
    // Placeholder - implement PS/2 keyboard initialization
    return error.NotImplemented;
}

/// Initialize task.
pub fn initTask(task: *Task, entry_point: usize, allocator: Allocator, set_up_stack: bool) Allocator.Error!void {
    task.vmm.payload = &paging.kernel_pml4;

    var stack = &task.kernel_stack;
    if (set_up_stack) {
        const data_offset = if (task.kernel) gdt.KERNEL_DATA_OFFSET else gdt.USER_DATA_OFFSET | 0b11;
        const code_offset = if (task.kernel) gdt.KERNEL_CODE_OFFSET else gdt.USER_CODE_OFFSET | 0b11;

        // Set up 64-bit stack frame
        const bottom = stack.len - 1;
        stack.*[bottom] = entry_point; // RIP
        stack.*[bottom - 1] = code_offset; // CS
        stack.*[bottom - 2] = 0x202; // RFLAGS
        stack.*[bottom - 3] = @intFromPtr(&stack.*[stack.len - 1]); // RSP
        stack.*[bottom - 4] = data_offset; // SS

        task.stack_pointer = @intFromPtr(&stack.*[bottom - 4]);
    }

    if (!task.kernel and !builtin.is_test) {
        // Create new PML4 for user task
        task.vmm.payload = try allocator.allocAdvanced(paging.Pml4Table, paging.PAGE_SIZE_4KB, 1, .exact);
        task.vmm.payload.* = paging.kernel_pml4;
    }
}

/// Get devices.
pub fn getDevices(allocator: Allocator) Allocator.Error![]Device {
    _ = allocator;
    // Placeholder - implement PCI enumeration
    return allocator.dupe(Device, &[_]Device{});
}

/// Get date/time.
pub fn getDateTime() DateTime {
    // Placeholder - implement RTC reading
    return .{
        .year = 2024,
        .month = 1,
        .day = 1,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
}

/// Initialize architecture.
pub fn init(mem_profile: *const MemProfile) void {
    gdt.init();
    idt.init();
    paging.init(mem_profile);
}

/// Runtime test check for user task state.
pub fn runtimeTestCheckUserTaskState(ctx: *const CpuState) bool {
    return ctx.rax == 0xCAFE and ctx.rbx == 0xBEEF;
}

/// Runtime test for memory/paging.
pub fn runtimeTestChecksMem(the_vmm: *const vmm.VirtualMemoryManager(VmmPayload)) void {
    var addr = the_vmm.start;
    while (addr < the_vmm.end and (the_vmm.isSet(addr) catch unreachable)) {
        addr += vmm.BLOCK_SIZE;
    }
    const should_fault = @ptrFromInt(*usize, addr).*;
    log.debug("This should not be printed: {x}\n", .{should_fault});
}

test "x86_64 arch" {
    std.testing.refAllDecls(@This());
}
