/* Linker script for x86_64 kernel */

ENTRY(boot)

KERNEL_PHYSADDR_START = 0x1000;
KERNEL_VADDR_START = 0xFFFFFFFF80000000;
KERNEL_ADDR_OFFSET = KERNEL_VADDR_START - KERNEL_PHYSADDR_START;

SECTIONS
{
    . = 1M;

    /* Physical start of the kernel */
    KERNEL_PHYSADDR_START = .;

    /* Bootloader section */
    .boot :
    {
        KEEP(*(.boot))
    }

    /* Multiboot header must be in first 8KB */
    .multiboot ALIGN(4K) :
    {
        KEEP(*(.multiboot))
    }

    /* Code section */
    .text ALIGN(4K) :
    {
        *(.text)
        *(.text.*)
    }

    /* Read-only data section */
    .rodata ALIGN(4K) :
    {
        *(.rodata)
        *(.rodata.*)
    }

    /* Data section */
    .data ALIGN(4K) :
    {
        *(.data)
        *(.data.*)
    }

    /* BSS section */
    .bss ALIGN(4K) :
    {
        *(COMMON)
        *(.bss)
        *(.bss.*)
    }

    /* Kernel stack */
    .stack ALIGN(16K) :
    {
        KERNEL_STACK_START = .;
        *(.stack)
        . = . + 0x40000; /* 256 KB stack */
        KERNEL_STACK_END = .;
    }

    /* Virtual address symbols */
    KERNEL_VADDR_START = . + KERNEL_ADDR_OFFSET;
    
    /* End symbols */
    KERNEL_PHYSADDR_END = .;
    KERNEL_VADDR_END = . + KERNEL_ADDR_OFFSET;

    /DISCARD/ :
    {
        *(.eh_frame)
    }
}
