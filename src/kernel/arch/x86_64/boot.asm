; x86_64 boot assembly
; This file contains the bootloader entry point and early initialization code for x86_64

section .boot
bits 32

; Multiboot2 header (must be in first 8KB of kernel)
align 8
multiboot_header:
    dd 0xE85250D6              ; Magic number
    dd 1                       ; Architecture (AMD64)
    dd multiboot_header_end - multiboot_header ; Header length
    dd -(0xE85250D6 + 1 + (multiboot_header_end - multiboot_header)) ; Checksum

%ifdef USE_FRAMEBUFFER
    ; Framebuffer tag
    dw 5                       ; Type (framebuffer)
    dw 0                       ; Flags
    dd framebuffer_tag_end - framebuffer_tag ; Size
    dd 800                     ; Width (0 = any)
    dd 600                     ; Height (0 = any)
    dd 0                       ; Depth (0 = any)
framebuffer_tag_end:
%endif

    ; End tag
    dw 0                       ; Type (end)
    dw 0                       ; Flags
    dd 8                       ; Size
multiboot_header_end:

; Entry point - called by bootloader with multiboot info in EAX/RDI
global boot
extern kmain
extern KERNEL_ADDR_OFFSET
extern paging_kernel_pml4

boot:
    ; Disable interrupts
    cli
    
    ; Check for Multiboot2 magic number
    cmp eax, 0x36d76289
    jne .no_multiboot2
    
    ; Load higher half kernel offset
    mov ecx, [KERNEL_ADDR_OFFSET]
    
    ; Set up initial page tables for identity mapping
    ; This is a minimal setup to get us into long mode
    call setup_paging
    
    ; Enable PAE
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    
    ; Load CR3 with our PML4
    mov eax, paging_kernel_pml4
    mov cr3, eax
    
    ; Enable long mode
    mov ecx, 0xC0000080        ; EFER MSR
    rdmsr
    or eax, 1 << 8             ; LME bit
    wrmsr
    
    ; Enable paging
    mov eax, cr0
    or eax, 1 << 31            ; PG bit
    mov cr0, eax
    
    ; Jump to 64-bit code
    lea rax, [.long_mode]
    jmp rax

.long_mode:
    bits 64
    
    ; Set up segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    
    ; Set up stack
    lea rsp, [KERNEL_STACK_END]
    
    ; Call kernel main
    ; RDI contains pointer to multiboot info structure
    push rdi
    call kmain
    
    ; If kmain returns, halt
.halt:
    hlt
    jmp .halt

.no_multiboot2:
    ; No Multiboot2 - halt
    hlt
    jmp $

; Set up initial identity-mapped page tables
setup_paging:
    push rbp
    mov rbp, rsp
    
    ; Clear page tables (assuming they're zeroed by linker)
    ; In a real implementation, would properly set up PML4, PDPT, PD, PT
    
    pop rbp
    ret

section .bss
align 4096

; Kernel stack (256 KB)
global KERNEL_STACK_START
global KERNEL_STACK_END
KERNEL_STACK_START:
    resb 262144
KERNEL_STACK_END:

section .data
align 4096

; Page tables for initial identity mapping
global paging_kernel_pml4
paging_kernel_pml4:
    resq 512

section .rodata
; Read-only data section

section .text
; Main code section
